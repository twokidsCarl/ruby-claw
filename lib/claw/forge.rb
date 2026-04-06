# frozen_string_literal: true

require "fileutils"

module Claw
  # Promotes eval-defined methods into formal Claw::Tool classes.
  # `/forge method_name` reads the method source, uses LLM to generate
  # a tool class, and writes it to `.ruby-claw/tools/`.
  module Forge
    TEMPLATE_PROMPT = <<~PROMPT
      Convert this Ruby method into a Claw::Tool class.

      Method source:
      ```ruby
      %{source}
      ```

      Output ONLY a complete Ruby file with this exact structure (no explanation):
      ```ruby
      class ClassName
        include Claw::Tool
        tool_name   "tool_name_here"
        description "One-line description of what this tool does"
        parameter   :param1, type: "String", required: true, desc: "..."
        # Add more parameters as needed

        def call(param1:)
          # Implementation (adapted from the method source above)
        end
      end
      ```

      Rules:
      - tool_name should be the method name in snake_case
      - Extract method parameters as tool parameters with appropriate types
      - The call method should have keyword arguments matching the parameters
      - Return a meaningful result (string or data structure)
    PROMPT

    class << self
      # Promote an eval-defined method to a formal tool class file.
      #
      # @param method_name [String] name of the method to promote
      # @param binding [Binding] caller's binding (to read definitions)
      # @param claw_dir [String] path to .ruby-claw/ directory
      # @return [Hash] { success: bool, path: String, message: String }
      def promote(method_name, binding:, claw_dir: nil)
        claw_dir ||= File.join(Dir.pwd, ".ruby-claw")
        tools_dir = File.join(claw_dir, "tools")
        FileUtils.mkdir_p(tools_dir)

        # 1. Read method source from tracked definitions
        source = find_source(method_name, binding)
        unless source
          return { success: false, message: "Method '#{method_name}' not found in definitions" }
        end

        # 2. Generate tool class via LLM (direct API call, no tools)
        prompt = format(TEMPLATE_PROMPT, source: source)
        backend = Mana::Backends::Base.for(Mana.config)
        response = backend.chat(
          system: "You are a Ruby code generator. Output only code, no explanations.",
          messages: [{ role: "user", content: prompt }],
          tools: [],
          model: Mana.config.model,
          max_tokens: 2048
        )
        raw = response.dig(:content, 0, :text) || response[:content]&.map { |c| c[:text] }&.compact&.join

        # 3. Extract Ruby code from response
        code = extract_ruby_code(raw.to_s)
        unless code
          return { success: false, message: "LLM did not generate valid Ruby code" }
        end

        # 4. Write to tools directory
        filename = "#{method_name.downcase.gsub(/[^a-z0-9_]/, '_')}.rb"
        path = File.join(tools_dir, filename)
        File.write(path, code)

        # 5. Refresh tool index if registry exists
        Claw.tool_registry&.index&.scan!

        { success: true, path: path, message: "Tool '#{method_name}' forged at #{path}" }
      rescue => e
        { success: false, message: "Forge failed: #{e.class}: #{e.message}" }
      end

      private

      def find_source(method_name, binding)
        receiver = binding.receiver
        defs = if receiver.instance_variable_defined?(:@__claw_definitions__)
                 receiver.instance_variable_get(:@__claw_definitions__)
               else
                 {}
               end

        # Try tracked definitions first
        source = defs[method_name.to_s] || defs[method_name.to_sym]
        return source if source

        # Try source_location as fallback
        meth = begin
          receiver.method(method_name.to_sym)
        rescue NameError
          nil
        end

        if meth&.source_location
          file, line = meth.source_location
          return nil unless file && File.exist?(file)
          lines = File.readlines(file)
          # Read from def line until matching end
          start = line - 1
          depth = 0
          result_lines = []
          lines[start..].each do |l|
            result_lines << l
            depth += 1 if l.match?(/\b(def|class|module|do|begin|if|unless|while|until|for|case)\b/)
            depth -= 1 if l.match?(/\bend\b/)
            break if depth <= 0 && result_lines.size > 1
          end
          result_lines.join
        end
      end

      def extract_ruby_code(text)
        # Extract code from ```ruby ... ``` blocks
        if text.match?(/```ruby\s*\n/)
          match = text.match(/```ruby\s*\n(.*?)```/m)
          return match[1].strip if match
        end

        # If the entire response looks like Ruby code
        if text.strip.match?(/\Aclass\s/)
          return text.strip
        end

        nil
      end
    end
  end
end
