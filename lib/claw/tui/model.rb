# frozen_string_literal: true

require "bubbletea"
require "bubbles"
require "io/console"

module Claw
  module TUI
    # MVU Model — central state for the TUI application.
    # Implements Bubbletea's init/update/view protocol.
    class Model
      attr_reader :runtime, :chat_history, :mode, :chat_viewport, :executor, :textarea,
                  :baseline_methods, :input_history

      def initialize(caller_binding)
        @caller_binding = caller_binding
        @runtime = init_runtime(caller_binding)
        @chat_history = []
        @mode = :normal  # :normal | :plan
        @scrolled_up = false
        @text_buffer = +""  # accumulates streaming text
        @input_history = []
        @history_index = nil
        @baseline_methods = caller_binding.eval("methods").dup

        # Bubbles components
        @chat_viewport = Bubbles::Viewport.new(width: 80, height: 20)
        @spinner = Bubbles::Spinner.new
        @spinner.style = Styles::SPINNER_STYLE
        @textarea = Bubbles::TextArea.new(width: 70, height: 1)
        @textarea.end_of_buffer_character = " "
        @textarea.placeholder = "Ruby expression, or /help"
        @textarea.placeholder_style = Lipgloss::Style.new.foreground(Styles::DIM_GRAY)
        @textarea.prompt = prompt_text
        @textarea.prompt_style = Lipgloss::Style.new.foreground(Styles::CYAN)
        @textarea.focus

        # Agent executor
        @executor = AgentExecutor.new(@runtime)

        # Runtime state change observer → deliver MVU messages
        @runtime&.on_state_change do |old_state, new_state, step|
          Bubbletea.send_message(StateChangeMsg.new(
            old_state: old_state, new_state: new_state, step: step
          ))
        end
      end

      def init
        @chat_history << { role: :system, content: "Claw agent ready" }
        [self, Bubbletea.batch(@spinner.tick, Bubbletea.tick(1.0) { TickMsg.new(time: Time.now) })]
      end

      def update(msg)
        cmd = case msg
              when Bubbletea::KeyMessage
                return handle_key(msg)
              when Bubbles::Spinner::TickMessage
                @spinner, spinner_cmd = @spinner.update(msg)
                Bubbletea.batch(spinner_cmd, Bubbletea.tick(1.0) { TickMsg.new(time: Time.now) })
              when TickMsg
                Bubbletea.tick(1.0) { TickMsg.new(time: Time.now) }
              when AgentTextMsg
                @text_buffer << msg.text
                Bubbletea.none
              when ToolCallMsg
                flush_text_buffer
                detail = format_tool_detail(msg.name, msg.input)
                @chat_history << { role: :tool_call, icon: "⚡", detail: detail }
                Bubbletea.none
              when ToolResultMsg
                @chat_history << { role: :tool_result, result: msg.result } unless msg.result.to_s.start_with?("ok:")
                Bubbletea.none
              when ExecutionDoneMsg
                flush_text_buffer
                write_trace(msg.trace)
                Claw.memory&.schedule_compaction
                Bubbletea.none
              when ExecutionErrorMsg
                flush_text_buffer
                @chat_history << { role: :error, content: msg.error.message }
                Bubbletea.none
              when CommandResultMsg
                handle_command_result(msg)
                Bubbletea.none
              when StateChangeMsg
                Bubbletea.none
              when Bubbletea::WindowSizeMessage
                Bubbletea.none
              else
                Bubbletea.none
              end
        [self, cmd]
      end

      def view
        h, w = IO.console&.winsize || [24, 80]
        w = 80 if w < 40
        h = 24 if h < 12
        Layout.render(self, w, h)
      end

      # --- Query methods for panels ---

      def last_snapshot_id
        @runtime&.snapshots&.last&.id || 0
      end

      def token_display
        ctx = Mana::Context.current
        used = ctx.token_count
        limit = Mana.config.context_window
        "#{format_tokens(used)}/#{format_tokens(limit)}"
      end

      def scrolled_up? = @scrolled_up
      def spinner_view = @spinner.view

      private

      def handle_key(msg)
        key = msg.to_s

        case key
        when "ctrl+d"
          save_state
          return [self, Bubbletea.quit]
        when "ctrl+c"
          if @executor.running?
            @executor.cancel!
            @chat_history << { role: :system, content: "interrupted" }
          else
            @textarea.reset
          end
          return [self, Bubbletea.none]
        when "pgup"
          @chat_viewport.page_up
          @scrolled_up = true
          return [self, Bubbletea.none]
        when "pgdown"
          @chat_viewport.page_down
          @scrolled_up = @chat_viewport.at_bottom? ? false : true
          return [self, Bubbletea.none]
        when "enter"
          text = @textarea.value.strip
          if text.empty?
            return [self, Bubbletea.none]
          elsif incomplete_ruby_input?(text)
            # Incomplete Ruby — let textarea insert newline for continuation
            @textarea, ta_cmd = @textarea.update(msg)
            return [self, ta_cmd]
          else
            # Complete input — submit
            return submit_textarea
          end
        when "up"
          if @textarea.line_count <= 1
            navigate_history(:up)
            return [self, Bubbletea.none]
          else
            @textarea, ta_cmd = @textarea.update(msg)
            return [self, ta_cmd]
          end
        when "down"
          if @textarea.line_count <= 1
            navigate_history(:down)
            return [self, Bubbletea.none]
          else
            @textarea, ta_cmd = @textarea.update(msg)
            return [self, ta_cmd]
          end
        when "tab"
          handle_tab_completion
          return [self, Bubbletea.none]
        end

        # All other keys → forward to textarea
        @textarea, ta_cmd = @textarea.update(msg)
        [self, ta_cmd]
      end

      def submit_textarea
        text = @textarea.value.strip
        @textarea.reset
        @textarea.prompt = prompt_text
        return [self, Bubbletea.none] if text.empty?

        # Busy guard — prevent concurrent executions
        if @executor.running? && !text.start_with?("/") && !text.match?(/\A(exit|quit|bye)\z/i)
          @chat_history << { role: :system, content: "Agent is busy — please wait for the current execution to finish." }
          return [self, Bubbletea.none]
        end

        # Exit
        if text.match?(/\A(exit|quit|bye)\z/i)
          save_state
          return [self, Bubbletea.quit]
        end

        @chat_history << { role: :user, content: text }
        @scrolled_up = false
        @input_history << text
        @history_index = nil

        if text.start_with?("/")
          handle_slash(text)
        else
          # Smart routing: try Ruby first, fallback to AI like Claw::Chat
          handle_smart_input(text)
        end
      end

      def handle_slash(text)
        cmd, *args = text.sub(/\A\//, "").split(" ", 2)
        arg = args.first

        if cmd == "help"
          cmds = [
            ["/help",         "show this help"],
            ["/ask <text>",   "ask AI (or just type natural language)"],
            ["/new",          "new session"],
            ["/status",       "runtime status"],
            ["/snapshot [l]", "create snapshot"],
            ["/rollback <id>","restore snapshot"],
            ["/diff [a] [b]", "diff snapshots"],
            ["/history",      "list snapshots"],
            ["/plan",         "toggle plan mode"],
            ["/cd <obj>",     "navigate into object"],
            ["/source <m>",   "show method source"],
            ["/doc <m>",      "show method docs"],
            ["/find <pat>",   "search methods"],
            ["/role [name]",  "switch role"],
            ["/evolve",       "run evolution"],
            ["/forge <m>",    "promote method"],
          ]
          max_cmd = cmds.map { |c, _| c.length }.max
          help = cmds.map { |c, d| "  %-#{max_cmd}s — %s" % [c, d] }
          help << ""
          help << "  Ruby expressions are evaluated directly."
          help << "  Natural language is sent to AI automatically."
          help << "  exit/quit — quit (or ctrl+d)"
          help << "  ↑↓ history | tab completion | pgup/pgdn scroll"
          @chat_history << { role: :system, content: help.join("\n") }
          return [self, Bubbletea.none]
        end

        if cmd == "ask"
          if arg && !arg.strip.empty?
            handle_llm(arg.strip)
          else
            @chat_history << { role: :error, content: "Usage: /ask <question>" }
          end
          return [self, Bubbletea.none]
        end

        if cmd == "new"
          @chat_history.clear
          @chat_history << { role: :system, content: "New session." }
          Mana::Context.current.reset! if Mana::Context.current.respond_to?(:reset!)
          @chat_viewport.content = ""
          @scrolled_up = false
          return [self, Bubbletea.none]
        end

        if cmd == "plan"
          @mode = @mode == :plan ? :normal : :plan
          @chat_history << { role: :system, content: "mode: #{@mode}" }
          return [self, Bubbletea.none]
        end

        # Object explorer commands
        case cmd
        when "cd"
          @nav_stack ||= []
          result = ObjectExplorer.cd(arg || "..", @caller_binding, @nav_stack)
          if result[:type] == :success
            @caller_binding = result[:data][:binding]
            @chat_history << { role: :system, content: "cd → #{result[:data][:label]}" }
          else
            @chat_history << { role: :error, content: result[:message] }
          end
          return [self, Bubbletea.none]
        when "source"
          result = ObjectExplorer.source(arg.to_s, @caller_binding)
          if result[:type] == :data
            @chat_history << { role: :system, content: "#{result[:data][:file]}:#{result[:data][:line]}\n#{result[:data][:source]}" }
          elsif result[:type] == :error && result[:message]&.include?("not found")
            # Try to find REPL-defined source from tracked definitions
            receiver = @caller_binding.eval("self")
            defs = receiver.instance_variable_defined?(:@__claw_definitions__) ?
              receiver.instance_variable_get(:@__claw_definitions__) : {}
            if defs[arg.to_s]
              @chat_history << { role: :system, content: "(defined in REPL)\n#{defs[arg.to_s]}" }
            else
              # Check if method exists but source is (eval)
              begin
                meth = @caller_binding.eval("method(:#{arg})")
                loc = meth.source_location
                if loc && loc[0] == "(eval)"
                  @chat_history << { role: :system, content: "Method '#{arg}' defined in REPL session (source not available)" }
                else
                  @chat_history << { role: :error, content: result[:message] }
                end
              rescue
                @chat_history << { role: :error, content: result[:message] }
              end
            end
          else
            @chat_history << { role: :error, content: result[:message] }
          end
          return [self, Bubbletea.none]
        when "doc"
          result = ObjectExplorer.doc(arg.to_s, @caller_binding)
          @chat_history << { role: :system, content: result[:data][:doc].to_s }
          return [self, Bubbletea.none]
        when "find"
          result = ObjectExplorer.find(arg.to_s, @caller_binding)
          if result[:type] == :data
            @chat_history << { role: :system, content: result[:data][:matches].join(", ") }
          else
            @chat_history << { role: :system, content: result[:message] }
          end
          return [self, Bubbletea.none]
        end

        result = Claw::Commands.dispatch(cmd, arg, runtime: @runtime)
        handle_command_result(CommandResultMsg.new(result: result, cmd: cmd))
        [self, Bubbletea.none]
      end

      def handle_smart_input(text)
        if ruby_syntax?(text)
          # Valid Ruby syntax → eval, with NameError/NoMethodError fallback to AI
          eval_result = @executor.eval_ruby(text, @caller_binding)
          if eval_result[:success]
            @chat_history << { role: :ruby, content: pretty_inspect(eval_result[:result]) }
            if eval_result[:result].is_a?(Symbol) && text.strip.match?(/\Adef\s/)
              track_definition(@caller_binding, text, eval_result[:result])
            end
            @runtime&.resources&.dig("binding")&.scan_binding
            return [self, Bubbletea.none]
          end

          err = eval_result[:error]
          if (err.is_a?(NameError) || err.is_a?(NoMethodError)) &&
             (text.include?(" ") || text.match?(/[^\x00-\x7F]/))
            # Multi-word or non-ASCII that failed as Ruby → fallback to AI
            handle_llm(text)
          else
            @chat_history << { role: :error, content: "#{err.class}: #{err.message}" }
            @runtime&.resources&.dig("binding")&.scan_binding
            [self, Bubbletea.none]
          end
        else
          # Not valid Ruby syntax → send to AI directly
          handle_llm(text)
        end
      end

      def handle_ruby(code)
        eval_result = @executor.eval_ruby(code, @caller_binding)
        if eval_result[:success]
          @chat_history << { role: :ruby, content: pretty_inspect(eval_result[:result]) }
          # Track method definitions for session persistence
          if eval_result[:result].is_a?(Symbol) && code.strip.match?(/\Adef\s/)
            track_definition(@caller_binding, code, eval_result[:result])
          end
        else
          @chat_history << { role: :error, content: "#{eval_result[:error].class}: #{eval_result[:error].message}" }
        end
        @runtime&.resources&.dig("binding")&.scan_binding
        [self, Bubbletea.none]
      end

      def ruby_syntax?(input)
        RubyVM::InstructionSequence.compile(input)
        true
      rescue SyntaxError
        false
      end

      def navigate_history(direction)
        return if @input_history.empty?

        if direction == :up
          if @history_index.nil?
            @saved_input = @textarea.value
            @history_index = @input_history.size - 1
          elsif @history_index > 0
            @history_index -= 1
          else
            return
          end
          @textarea.reset
          @textarea.value = @input_history[@history_index]
        else # :down
          return if @history_index.nil?
          if @history_index < @input_history.size - 1
            @history_index += 1
            @textarea.reset
            @textarea.value = @input_history[@history_index]
          else
            @history_index = nil
            @textarea.reset
            @textarea.value = @saved_input || ""
          end
        end
      end

      def handle_tab_completion
        prefix = @textarea.value
        return if prefix.empty?

        candidates = InputHandler.completions(prefix, binding: @caller_binding, memory: Claw.memory)
        return if candidates.empty?

        if candidates.size == 1
          @textarea.reset
          @textarea.value = candidates.first
        else
          # Show candidates in chat (up to 20)
          display = candidates.first(20).join("  ")
          display += "  ..." if candidates.size > 20
          @chat_history << { role: :system, content: display }
        end
      end


      def handle_llm(text)
        # Extract @file references and inject file context
        refs = FileCard.extract_refs(text)
        unless refs.empty?
          refs.each do |ref|
            paths = FileCard.resolve(ref)
            paths.each do |path|
              @chat_history << { role: :system, content: FileCard.render_card(path) }
              text = "#{text}\n\n#{FileCard.read_for_context(path)}"
            end
          end
        end

        @executor.execute(text, @caller_binding) do |event|
          Bubbletea.send_message(event)
        end
        [self, Bubbletea.none]
      end

      def handle_command_result(msg)
        result = msg.result
        case result[:type]
        when :success
          @chat_history << { role: :system, content: "✓ #{result[:message]}" }
        when :error
          @chat_history << { role: :error, content: result[:message] }
        when :info
          @chat_history << { role: :system, content: result[:message] }
        when :data
          case msg.cmd
          when "diff"
            data = result[:data]
            lines = ["Diff ##{data[:from]} → ##{data[:to]}:"]
            data[:diffs].each do |name, d|
              lines << "  #{name}:"
              d.each_line { |l| lines << "    #{l.rstrip}" }
            end
            @chat_history << { role: :system, content: lines.join("\n") }
          when "history"
            lines = result[:data][:snapshots].map { |s| "  ##{s[:id]} #{s[:label]} — #{s[:timestamp]}" }
            @chat_history << { role: :system, content: lines.join("\n") }
          when "status"
            @chat_history << { role: :system, content: result[:data][:markdown] }
          when "evolve"
            evo = result[:data]
            msg_text = case evo[:status]
                       when :accept then "✓ accepted: #{evo[:proposal]}"
                       when :reject then "✗ rejected: #{evo[:proposal] || 'n/a'}"
                       when :skip then "· skipped: #{evo[:reason]}"
                       else result[:message]
                       end
            @chat_history << { role: :system, content: msg_text }
          else
            @chat_history << { role: :system, content: result[:message] }
          end
        end
      end

      def flush_text_buffer
        return if @text_buffer.empty?
        @chat_history << { role: :agent, content: @text_buffer.dup }
        @text_buffer.clear
      end

      def format_tool_detail(name, input)
        input ||= {}
        case name
        when "call_func"
          func = input[:name] || input["name"]
          args = input[:args] || input["args"] || []
          desc = func.to_s
          desc += "(#{args.map(&:inspect).join(', ')})" if args.any?
          desc
        when "read_var", "write_var"
          var = input[:name] || input["name"]
          val = input[:value] || input["value"]
          val ? "#{var} = #{val.inspect[0, 60]}" : var.to_s
        when "read_attr", "write_attr"
          obj = input[:obj] || input["obj"]
          attr = input[:attr] || input["attr"]
          "#{obj}.#{attr}"
        when "remember"
          "remember: #{(input[:content] || input["content"]).to_s[0, 60]}"
        when "knowledge"
          topic = input[:topic] || input["topic"]
          "knowledge(#{topic})"
        else
          name.to_s
        end
      end

      def incomplete_ruby_input?(text)
        return false if text.start_with?("/")  # slash commands are never multiline
        InputHandler.incomplete?(text)
      end

      def prompt_text
        @mode == :plan ? "plan> " : ">> "
      end


      def write_trace(trace_data)
        return unless trace_data
        claw_dir = File.join(Dir.pwd, ".ruby-claw")
        return unless File.directory?(claw_dir)
        Claw::Trace.write(trace_data, claw_dir)
      rescue
        # ignore trace write failures
      end

      def save_state
        Claw::Serializer.save(@caller_binding, File.join(Dir.pwd, ".ruby-claw")) if Claw.config.persist_session
        Claw.memory&.save_session
      rescue
        # ignore save failures
      end

      def track_definition(caller_binding, code, method_name)
        receiver = caller_binding.receiver
        defs = receiver.instance_variable_defined?(:@__claw_definitions__) ?
          receiver.instance_variable_get(:@__claw_definitions__) : {}
        defs[method_name.to_s] = code
        receiver.instance_variable_set(:@__claw_definitions__, defs)
      end

      def pretty_inspect(obj)
        require "pp"
        PP.pp(obj, +"", 60).chomp
      rescue
        obj.inspect
      end

      def format_tokens(n)
        n < 1000 ? n.to_s : "#{(n / 1000.0).round(1)}k"
      end

      def init_runtime(caller_binding)
        runtime = Claw::Runtime.new

        context = Mana::Context.current
        runtime.register("context", Claw::Resources::ContextResource.new(context))

        memory = Claw.memory
        runtime.register("memory", Claw::Resources::MemoryResource.new(memory)) if memory

        runtime.register("binding", Claw::Resources::BindingResource.new(caller_binding))

        claw_dir = File.join(Dir.pwd, ".ruby-claw")
        if File.directory?(claw_dir)
          runtime.register("filesystem", Claw::Resources::FilesystemResource.new(claw_dir))
        end

        runtime.snapshot!(label: "session_start")
        runtime
      rescue => e
        $stderr.puts "  ⚠ runtime init failed: #{e.message}" if Mana.config.verbose
        nil
      end
    end
  end
end
