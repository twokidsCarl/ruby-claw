# frozen_string_literal: true

require "mana"
require "marshal-md"
require_relative "claw/version"
require_relative "claw/config"
require_relative "claw/memory_store"
require_relative "claw/memory"
require_relative "claw/knowledge"
require_relative "claw/resource"
require_relative "claw/runtime"
require_relative "claw/resources/context_resource"
require_relative "claw/resources/memory_resource"
require_relative "claw/resources/filesystem_resource"
require_relative "claw/resources/binding_resource"
require_relative "claw/resources/worktree_resource"
require_relative "claw/serializer"
require_relative "claw/trace"
require_relative "claw/init"
require_relative "claw/evolution"
require_relative "claw/child_runtime"
require_relative "claw/tool"
require_relative "claw/tool_index"
require_relative "claw/tool_registry"
require_relative "claw/forge"
require_relative "claw/auto_forge"
require_relative "claw/hub"
require_relative "claw/commands"
require_relative "claw/plan_mode"
require_relative "claw/roles"
require_relative "claw/console"
require_relative "claw/cli"
require_relative "claw/chat"
require_relative "claw/tui/tui"

module Claw
  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield(config) if block_given?
      config
    end

    # Embedded API: send a single prompt to the agent.
    # For interactive use, run `claw` to launch the TUI.
    def chat(prompt = nil)
      if prompt
        engine = Mana::Engine.new(binding.of_caller(1))
        engine.execute(prompt)
      else
        warn "Claw.chat without arguments is deprecated. Use `claw` command to launch the TUI."
        TUI.start(binding.of_caller(1))
      end
    end

    def memory
      Memory.current
    end

    def incognito(&block)
      Memory.incognito(&block)
    end

    def tool_registry
      @tool_registry
    end

    def init_tool_registry(tools_dir: nil, hub: nil)
      tools_dir ||= File.join(Dir.pwd, ".ruby-claw", "tools")
      @tool_registry = ToolRegistry.new(tools_dir: tools_dir, hub: hub)
    end

    def reset!
      @config = Config.new
      @tool_registry = nil
      Claw::Tool.tool_classes.clear
      Thread.current[:claw_memory] = nil
      Thread.current[:mana_context] = nil
    end
  end
end

# Register Claw's remember tool via Mana's tool registration interface.
Mana.register_tool(
  {
    name: "remember",
    description: "Store a fact in long-term memory. This memory persists across script executions. Use when the user explicitly asks to remember something.",
    input_schema: {
      type: "object",
      properties: { content: { type: "string", description: "The fact to remember" } },
      required: ["content"]
    }
  }
) do |input|
  memory = Claw.memory  # nil when incognito
  if memory
    entry = memory.remember(input["content"])
    "Remembered (id=#{entry[:id]}): #{input['content']}"
  else
    "Memory not available"
  end
end

# Register prompt section to inject long-term memories into system prompt.
Mana.register_prompt_section do
  memory = Claw.memory
  next nil unless memory && !memory.long_term.empty?

  lines = ["Long-term memories (persistent background context):"]
  memory.long_term.each { |m| lines << "- #{m[:content]}" }
  lines << ""
  lines << "You have a `remember` tool to store facts in long-term memory."
  lines << "After completing a task, proactively use `remember` to store:"
  lines << "- User preferences you observed (coding style, language, formatting)"
  lines << "- Project characteristics (tech stack, architecture, key files)"
  lines << "- Effective strategies that worked well"
  lines << "- Corrections the user made (to avoid repeating mistakes)"
  lines << "Do not wait to be asked — remember useful context proactively."
  lines.join("\n")
end

# Register prompt section to inject active role into system prompt.
Mana.register_prompt_section do
  role = Claw::Roles.current
  next nil unless role

  "Active role: #{role[:name]}\n#{role[:content]}"
end

# Register search_tools — agent uses this to discover available project/hub tools.
Mana.register_tool(
  {
    name: "search_tools",
    description: "Search for available tools by keyword. Returns matching tools that can be loaded with load_tool.",
    input_schema: {
      type: "object",
      properties: { query: { type: "string", description: "What capability you need" } },
      required: ["query"]
    }
  }
) do |input|
  registry = Claw.tool_registry
  unless registry
    next "Tool registry not initialized. Run `claw init` first."
  end

  results = registry.search(input["query"])
  if results.empty?
    "No tools found matching '#{input['query']}'"
  else
    lines = results.map do |r|
      status = r[:loaded] ? " [loaded]" : ""
      "- #{r[:name]}: #{r[:description]} (#{r[:source]}#{status})"
    end
    "Found #{results.size} tool(s):\n#{lines.join("\n")}"
  end
end

# Register load_tool — agent uses this to dynamically load a discovered tool.
Mana.register_tool(
  {
    name: "load_tool",
    description: "Load a tool to make it available for use in the current session. Use search_tools first to find available tools.",
    input_schema: {
      type: "object",
      properties: { tool_name: { type: "string", description: "Name of the tool to load" } },
      required: ["tool_name"]
    }
  }
) do |input|
  registry = Claw.tool_registry
  unless registry
    next "Tool registry not initialized. Run `claw init` first."
  end

  registry.load(input["tool_name"])
end

# Register Claw's enhanced knowledge provider.
Mana.config.knowledge_provider = Claw::Knowledge
