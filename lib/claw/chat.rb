# frozen_string_literal: true

module Claw
  # Interactive chat mode — enter with Claw.chat to talk to the agent in your Ruby runtime.
  # Supports streaming output, colored prompts, and full access to the caller's binding.
  # Auto-detects Ruby code vs natural language. Use '!' prefix to force Ruby execution.
  module Chat
    USER_PROMPT  = "\e[36mclaw>\e[0m "    # cyan
    CLAW_PREFIX  = "\e[33mclaw>\e[0m "    # yellow
    RUBY_PREFIX  = "\e[35m=>\e[0m "       # magenta
    THINK_COLOR  = "\e[3;36m"             # italic cyan
    TOOL_COLOR   = "\e[2;33m"             # dim yellow
    RESULT_COLOR = "\e[2;32m"             # dim green
    CODE_COLOR   = "\e[36m"               # cyan for code
    BOLD         = "\e[1m"                # bold
    ERROR_COLOR  = "\e[31m"               # red
    DIM          = "\e[2m"                # dim
    RESET        = "\e[0m"

    CONT_PROMPT  = "\e[2m  \e[0m"
    EXIT_COMMANDS = /\A(exit|quit|bye|q)\z/i

    HISTORY_FILE = File.join(Dir.home, ".claw_history")
    HISTORY_MAX  = 1000

    def self.start(caller_binding)
      require "reline"
      load_history
      load_compiled_methods(caller_binding)
      restore_runtime(caller_binding)
      puts "#{DIM}Claw agent · type 'exit' to quit#{RESET}"
      puts

      loop do
        input = read_input
        break if input.nil?
        next if input.strip.empty?
        break if input.strip.match?(EXIT_COMMANDS)

        if input.start_with?("!")
          eval_ruby(caller_binding, input[1..].strip)
        elsif ruby_syntax?(input)
          eval_ruby(caller_binding, input) { run_claw(caller_binding, input) }
        else
          run_claw(caller_binding, input)
        end
        puts
      end

      # Save state on exit
      save_runtime(caller_binding)
      Claw.memory&.save_session
      save_history
      puts "#{DIM}bye!#{RESET}"
    end

    def self.load_history
      return unless File.exist?(HISTORY_FILE)

      File.readlines(HISTORY_FILE, chomp: true).last(HISTORY_MAX).each do |line|
        Reline::HISTORY << line
      end
    rescue StandardError
      # ignore corrupt history
    end
    private_class_method :load_history

    # Reload mana def compiled methods from .mana_cache/ on session start.
    # These are pre-compiled Ruby methods that don't need LLM calls.
    def self.load_compiled_methods(caller_binding)
      cache_dir = Mana::Compiler.cache_dir
      return unless Dir.exist?(cache_dir)

      count = 0
      Dir.glob(File.join(cache_dir, "*.rb")).each do |path|
        code = File.read(path)
        # Skip the header comment lines, eval the method definition
        caller_binding.eval(code, path, 1)
        count += 1
      rescue => e
        $stderr.puts "#{DIM}  ⚠ could not load #{File.basename(path)}: #{e.message}#{RESET}" if Mana.config.verbose
      end
      puts "#{DIM}  ✓ loaded #{count} compiled methods#{RESET}" if count > 0
    rescue => e
      # Don't crash on cache loading failure
    end
    private_class_method :load_compiled_methods

    # Save Ruby runtime state (variables + method definitions) to .mana/
    def self.save_runtime(caller_binding)
      return unless Claw.config.persist_session
      dir = File.join(Dir.pwd, ".mana")
      Claw::Serializer.save(caller_binding, dir)
    rescue => e
      $stderr.puts "#{DIM}  ⚠ could not save runtime: #{e.message}#{RESET}" if Mana.config.verbose
    end
    private_class_method :save_runtime

    # Restore Ruby runtime state from .mana/
    def self.restore_runtime(caller_binding)
      return unless Claw.config.persist_session
      dir = File.join(Dir.pwd, ".mana")
      return unless File.exist?(File.join(dir, "values.json")) || File.exist?(File.join(dir, "definitions.rb"))

      warnings = Claw::Serializer.restore(caller_binding, dir)
      warnings.each { |w| puts "#{DIM}  ⚠ #{w}#{RESET}" } if warnings.any?
      puts "#{DIM}  ✓ runtime restored#{RESET}"
    rescue => e
      puts "#{DIM}  ⚠ could not restore runtime: #{e.message}#{RESET}"
    end
    private_class_method :restore_runtime

    # Track method definitions for session persistence
    def self.track_definition(caller_binding, code, method_name)
      receiver = caller_binding.receiver
      defs = receiver.instance_variable_defined?(:@__claw_definitions__) ?
        receiver.instance_variable_get(:@__claw_definitions__) : {}
      defs[method_name.to_s] = code
      receiver.instance_variable_set(:@__claw_definitions__, defs)
    end
    private_class_method :track_definition

    def self.save_history
      lines = Reline::HISTORY.to_a.last(HISTORY_MAX)
      File.write(HISTORY_FILE, lines.join("\n") + "\n")
    rescue StandardError
      # ignore write failures
    end
    private_class_method :save_history

    def self.read_input
      buffer = Reline.readline(USER_PROMPT, true)
      return nil if buffer.nil?

      while incomplete_ruby?(buffer)
        line = Reline.readline(CONT_PROMPT, false)
        break if line.nil?
        buffer += "\n" + line
      end
      buffer
    end
    private_class_method :read_input

    def self.ruby_syntax?(input)
      RubyVM::InstructionSequence.compile(input)
      true
    rescue SyntaxError
      false
    end
    private_class_method :ruby_syntax?

    def self.incomplete_ruby?(code)
      RubyVM::InstructionSequence.compile(code)
      false
    rescue SyntaxError => e
      e.message.include?("unexpected end-of-input") ||
        e.message.include?("unterminated")
    end
    private_class_method :incomplete_ruby?

    def self.eval_ruby(caller_binding, code)
      result = caller_binding.eval(code)
      # Track method definitions: `def method_name` returns a Symbol in Ruby 3+
      track_definition(caller_binding, code, result) if result.is_a?(Symbol) && code.strip.match?(/\Adef\s/)
      puts "#{RUBY_PREFIX}#{result.inspect}"
    rescue NameError, NoMethodError => e
      # Fallback to LLM for natural language (multi-word or non-ASCII like Chinese)
      if block_given? && (code.include?(" ") || code.match?(/[^\x00-\x7F]/))
        yield
      else
        puts "#{ERROR_COLOR}#{e.class}: #{e.message}#{RESET}"
      end
    rescue => e
      puts "#{ERROR_COLOR}#{e.class}: #{e.message}#{RESET}"
    end
    private_class_method :eval_ruby

    # --- LLM execution with streaming + markdown rendering ---

    def self.run_claw(caller_binding, input)
      streaming_text = false
      in_code_block = false
      line_buffer = +""
      engine = Mana::Engine.new(caller_binding)

      begin
        result = engine.execute(input) do |type, *args|
          case type
          when :text
            unless streaming_text
              print CLAW_PREFIX
              streaming_text = true
            end

            line_buffer << args[0].to_s
            while (idx = line_buffer.index("\n"))
              line = line_buffer.slice!(0, idx + 1)
              in_code_block = render_line(line.chomp, in_code_block)
              puts
            end

          when :tool_start
            flush_line_buffer(line_buffer, in_code_block) if streaming_text
            streaming_text = false
            in_code_block = false
            line_buffer.clear
            name, input_data = args
            detail = format_tool_call(name, input_data)
            puts "#{TOOL_COLOR}  ⚡ #{detail}#{RESET}"

          when :tool_end
            name, result_str = args
            summary = truncate(result_str.to_s, 120)
            puts "#{RESULT_COLOR}  ↩ #{summary}#{RESET}" unless summary.start_with?("ok:")
          end
        end

        flush_line_buffer(line_buffer, in_code_block) if streaming_text

        unless streaming_text
          display = case result
                    when Hash then result.inspect
                    when nil then nil
                    when String then render_markdown(result)
                    else result.inspect
                    end
          puts "#{CLAW_PREFIX}#{display}" if display
        end

        # Schedule compaction after each exchange
        Claw.memory&.schedule_compaction
      rescue Mana::LLMError, Mana::MaxIterationsError => e
        flush_line_buffer(line_buffer, in_code_block) if streaming_text
        puts "#{ERROR_COLOR}error: #{e.message}#{RESET}"
      end
    end
    private_class_method :run_claw

    # --- Markdown rendering ---

    def self.render_line(line, in_code_block)
      if line.strip.start_with?("```")
        if in_code_block
          return false
        else
          return true
        end
      end

      if in_code_block
        print "  #{CODE_COLOR}#{line}#{RESET}"
      else
        print render_markdown_inline(line)
      end
      in_code_block
    end
    private_class_method :render_line

    def self.flush_line_buffer(buffer, in_code_block)
      return if buffer.empty?
      text = buffer.dup
      buffer.clear
      if in_code_block
        print "  #{CODE_COLOR}#{text}#{RESET}"
      else
        print render_markdown_inline(text)
      end
      puts
    end
    private_class_method :flush_line_buffer

    def self.render_markdown_inline(text)
      text
        .gsub(/\*\*(.+?)\*\*/, "#{BOLD}\\1#{RESET}")
        .gsub(/(?<!`)`([^`]+)`(?!`)/, "#{CODE_COLOR}\\1#{RESET}")
        .gsub(/^\#{1,3}\s+(.+)/) { BOLD + $1 + RESET }
    end
    private_class_method :render_markdown_inline

    def self.render_markdown(text)
      lines = text.lines
      result = +""
      in_code = false
      lines.each do |line|
        stripped = line.strip
        if stripped.start_with?("```")
          in_code = !in_code
          next
        end
        if in_code
          result << "  #{CODE_COLOR}#{line.rstrip}#{RESET}\n"
        else
          result << render_markdown_inline(line.rstrip) << "\n"
        end
      end
      result.chomp
    end
    private_class_method :render_markdown

    # --- Tool formatting helpers ---

    def self.format_tool_call(name, input)
      case name
      when "call_func"
        func = input[:name] || input["name"]
        args = input[:args] || input["args"] || []
        body = input[:body] || input["body"]
        desc = func.to_s
        desc += "(#{args.map(&:inspect).join(', ')})" if args.any?
        desc += " { #{truncate(body, 40)} }" if body
        desc
      when "read_var", "write_var"
        var = input[:name] || input["name"]
        val = input[:value] || input["value"]
        val ? "#{var} = #{truncate(val.inspect, 60)}" : var.to_s
      when "read_attr", "write_attr"
        obj = input[:obj] || input["obj"]
        attr = input[:attr] || input["attr"]
        "#{obj}.#{attr}"
      when "remember"
        content = input[:content] || input["content"]
        "remember: #{truncate(content.to_s, 60)}"
      when "knowledge"
        topic = input[:topic] || input["topic"]
        "knowledge(#{topic})"
      else
        name.to_s
      end
    end
    private_class_method :format_tool_call

    def self.truncate(str, max)
      str.length > max ? "#{str[0, max]}..." : str
    end
    private_class_method :truncate
  end
end
