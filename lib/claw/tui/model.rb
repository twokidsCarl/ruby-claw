# frozen_string_literal: true

require "bubbletea"
require "bubbles"
require "io/console"
require "pp"

begin
  require "bubblezone"
rescue LoadError
  # bubblezone gem ships versioned native extensions (e.g. 4.0/bubblezone.bundle)
  # but its loader may not route by Ruby version. Patch and retry.
  begin
    spec = Gem::Specification.find_by_name("bubblezone")
    major, minor, = RUBY_VERSION.split(".")
    versioned_dir = File.join(spec.gem_dir, "lib", "bubblezone", "#{major}.#{minor}")
    if File.directory?(versioned_dir)
      # Add versioned dir so require_relative "bubblezone/bubblezone" resolves
      target = File.join(spec.gem_dir, "lib", "bubblezone", "bubblezone.bundle")
      source = File.join(versioned_dir, "bubblezone.bundle")
      unless File.exist?(target)
        File.symlink(source, target)
      end
      require "bubblezone"
    end
  rescue LoadError, Gem::MissingSpecError, Errno::EEXIST, Errno::EACCES
    # mouse click zones will be disabled but scroll/drag still work.
  end
end

module Claw
  module TUI
    # MVU Model — central state for the TUI application.
    # Implements Bubbletea's init/update/view protocol.
    class Model
      attr_reader :runtime, :chat_history, :mode, :chat_viewport, :executor, :textarea,
                  :baseline_methods, :baseline_vars, :zone, :tab_hint, :history
      attr_accessor :chat_ratio, :dragging_divider

      # Cap @chat_history to avoid unbounded growth in long sessions. When the
      # array exceeds MAX, drop the oldest TRIM_CHUNK entries in one go (FIFO)
      # and inject a synthetic marker so the user knows older scrollback was
      # truncated. Pruning is O(1) per update tick when under the cap.
      CHAT_HISTORY_MAX        = 2000
      CHAT_HISTORY_TRIM_CHUNK = 500

      # Back-compat: tests and callers still ask for `input_history`. Delegate
      # to HistoryManager so the historical name keeps working.
      def input_history
        @history.entries
      end

      def initialize(caller_binding, baseline_methods: nil, baseline_vars: nil)
        @caller_binding = caller_binding
        @runtime = init_runtime(caller_binding)
        @chat_history = []
        @mode = :normal  # :normal | :plan
        @scrolled_up = false
        @text_buffer = +""  # accumulates streaming text
        @history = HistoryManager.new
        @chat_ratio = 0.70
        @dragging_divider = false
        @tab_hint = nil
        @view_width = 80
        @view_height = 24
        @zone = defined?(Bubblezone::Manager) ? Bubblezone::Manager.new : nil
        @baseline_methods = baseline_methods || begin
          caller_binding.eval("methods | private_methods").dup
        rescue
          []
        end
        @baseline_vars = baseline_vars || begin
          caller_binding.local_variables.map(&:to_s)
        rescue
          []
        end

        # Bubbles components
        @chat_viewport = Bubbles::Viewport.new(width: 80, height: 20)
        @spinner = Bubbles::Spinner.new
        @spinner.style = Styles::SPINNER_STYLE
        @textarea = RubyTextArea.new(width: 70, height: 1)
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
              when Bubbletea::MouseMessage
                return handle_mouse(msg)
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
                @view_width = msg.width
                @view_height = msg.height
                Bubbletea.none
              else
                Bubbletea.none
              end
        prune_chat_history!
        [self, cmd]
      end

      def view
        w = @view_width
        h = @view_height
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

      # Drop the oldest TRIM_CHUNK messages once @chat_history exceeds MAX.
      # Replaces them with a single :system marker so the user knows older
      # scrollback isn't gone "silently". Called from #update on every tick;
      # the early return makes the under-cap path effectively free.
      def prune_chat_history!
        return if @chat_history.size <= CHAT_HISTORY_MAX

        dropped = @chat_history.shift(CHAT_HISTORY_TRIM_CHUNK).size
        @chat_history.unshift(
          { role: :system, content: "[trimmed #{dropped} older messages]" }
        )
      end

      def handle_mouse(msg)
        w = @view_width
        h = @view_height
        divider_x = (w * @chat_ratio).to_i

        if msg.wheel?
          if msg.button == Bubbletea::MouseMessage::BUTTON_WHEEL_UP
            @chat_viewport.scroll_up(3)
            @scrolled_up = true
          else
            @chat_viewport.scroll_down(3)
            @scrolled_up = @chat_viewport.at_bottom? ? false : true
          end
        elsif msg.press?
          if msg.left?
            # Click near divider (±2 cols) and below status bar → start drag
            if (msg.x - divider_x).abs <= 2 && msg.y > 1
              @dragging_divider = true
            else
              handle_mouse_click(msg, w, h)
            end
          end
        elsif msg.motion?
          if @dragging_divider
            @chat_ratio = (msg.x.to_f / w).clamp(0.3, 0.85)
          end
        elsif msg.release?
          @dragging_divider = false
        end

        [self, Bubbletea.none]
      end

      def handle_mouse_click(msg, width, height)
        return unless @zone
        hit = @zone.find_in_bounds(msg.x, msg.y)
        return unless hit
        zone_id, _zone_info = hit

        case zone_id
        when /\Asnap_(\d+)\z/
          snap_id = $1.to_i
          @chat_history << {
            role: :system,
            content: "Snapshot ##{snap_id} selected. Type /rollback #{snap_id} to restore."
          }

        when /\Amem_(\d+)\z/
          mem_id = $1.to_i
          fact = Claw.memory&.long_term&.find { |m| m[:id] == mem_id }
          if fact
            @chat_history << { role: :system, content: "Memory ##{mem_id}: #{fact[:content]}" }
          end

        when /\Atool_(.+)\z/
          tool_name = $1
          @chat_history << {
            role: :system,
            content: "Tool: #{tool_name}. Use /forge #{tool_name} to promote."
          }

        when /\Afold_(\d+)\z/
          idx = $1.to_i
          if idx < @chat_history.size
            m = @chat_history[idx]
            if m[:folded_full]
              m[:content] = m[:folded_full]
              m.delete(:folded_full)
            end
          end
        end
      end

      def handle_key(msg)
        key = msg.to_s

        # Clear transient tab hint on any non-tab key
        @tab_hint = nil unless key == "tab"

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
            # Auto-indent: insert spaces at cursor on the new line
            indent = InputHandler.indent_level(@textarea.value)
            @textarea.indent_current_line(" " * indent) if indent > 0
            return [self, ta_cmd]
          else
            # Complete input — submit
            return submit_textarea
          end
        when "up"
          if @textarea.line_count <= 1 || @textarea.row == 0
            navigate_history(:up)
            return [self, Bubbletea.none]
          else
            @textarea, ta_cmd = @textarea.update(msg)
            return [self, ta_cmd]
          end
        when "down"
          if @textarea.line_count <= 1 || @textarea.row == @textarea.line_count - 1
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

        # Auto-dedent: when user completes typing "end", reduce indent.
        # Both the check and mutation live inside RubyTextArea so the Bubbles
        # internal-state access is contained to one file.
        if @textarea.line_count > 1 && @textarea.current_line_is_lone_end?
          @textarea.dedent_current_line(2)
        end

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
        @history.record(text)

        if text.start_with?("/")
          handle_slash(text)
        else
          # Smart routing: try Ruby first, fallback to AI like Claw::Chat
          handle_smart_input(text)
        end
      end

      # All slash-command logic lives in Claw::TUI::CommandProcessor; this
      # method is now just the dispatch entry point. Kept on Model so the
      # call site in `submit_textarea` reads naturally.
      def handle_slash(text)
        CommandProcessor.dispatch(self, text)
      end

      def handle_smart_input(text)
        if ruby_syntax?(text)
          # Valid Ruby syntax → eval, with NameError/NoMethodError fallback to AI
          eval_result = @executor.eval_ruby(text, @caller_binding)
          if eval_result[:success]
            @chat_history << { role: :system, content: eval_result[:output] } if eval_result[:output]
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
            return handle_llm(text)
          else
            @chat_history << { role: :error, content: "#{err.class}: #{err.message}" }
            @runtime&.resources&.dig("binding")&.scan_binding
            return [self, Bubbletea.none]
          end
        else
          # Not valid Ruby syntax → send to AI directly
          return handle_llm(text)
        end
      end

      def handle_ruby(code)
        eval_result = @executor.eval_ruby(code, @caller_binding)
        if eval_result[:success]
          @chat_history << { role: :system, content: eval_result[:output] } if eval_result[:output]
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

      # Delegate to HistoryManager. Model owns the textarea mutation; the
      # manager owns the navigation state — clean separation.
      def navigate_history(direction)
        recalled = direction == :up ? @history.up(@textarea.value) : @history.down
        return if recalled.nil?
        @textarea.reset
        @textarea.value = recalled
      end

      def handle_tab_completion
        prefix = @textarea.value
        return if prefix.empty?

        candidates = InputHandler.completions(prefix, binding: @caller_binding, memory: Claw.memory)
        return if candidates.empty?

        if candidates.size == 1
          @textarea.reset
          @textarea.value = candidates.first
          @tab_hint = nil
        else
          # Show candidates as transient hint right above input bar
          display = candidates.first(20).join("  ")
          display += "  ..." if candidates.size > 20
          @tab_hint = display
        end
      rescue => e
        # Tab completion should never crash the TUI
        nil
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
        Claw::Serializer.save(@caller_binding, File.join(Dir.pwd, ".ruby-claw"), baseline_vars: @baseline_vars) if Claw.config.persist_session
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
