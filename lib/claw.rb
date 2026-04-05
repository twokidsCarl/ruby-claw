# frozen_string_literal: true

require "mana"
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
require_relative "claw/serializer"
require_relative "claw/chat"

module Claw
  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield(config) if block_given?
      config
    end

    def chat
      Chat.start(binding.of_caller(1))
    end

    def memory
      Memory.current
    end

    def incognito(&block)
      Memory.incognito(&block)
    end

    def reset!
      @config = Config.new
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
  lines << "You have a `remember` tool to store new facts in long-term memory when the user asks."
  lines.join("\n")
end

# Register Claw's enhanced knowledge provider.
Mana.config.knowledge_provider = Claw::Knowledge
