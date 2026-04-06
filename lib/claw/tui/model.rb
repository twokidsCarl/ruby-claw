# frozen_string_literal: true

require "bubbletea"
require "bubbles"
require "io/console"

module Claw
  module TUI
    # MVU Model — central state for the TUI application.
    # Implements Bubbletea's init/update/view protocol.
    class Model
      attr_reader :runtime, :chat_history, :mode, :chat_viewport, :executor
      attr_accessor :input_text

      def initialize(caller_binding)
        @caller_binding = caller_binding
        @runtime = init_runtime(caller_binding)
        @chat_history = []
        @mode = :normal  # :normal | :plan
        @input_text = ""
        @input_focused = true
        @scrolled_up = false
        @text_buffer = +""  # accumulates streaming text

        # Bubbles components
        @chat_viewport = Bubbles::Viewport.new(width: 80, height: 20)
        @spinner = Bubbles::Spinner.new
        @spinner.style = Styles::SPINNER_STYLE

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
        @chat_history << { role: :system, content: "Claw agent ready · type 'exit' to quit" }
        cmd = @spinner.init
        Bubbletea.batch(cmd, Bubbletea.tick(1.0) { TickMsg.new(time: Time.now) })
      end

      def update(msg)
        case msg
        when Bubbletea::KeyMessage
          handle_key(msg)
        when TickMsg
          cmd = @spinner.update(@spinner.tick)
          Bubbletea.batch(cmd, Bubbletea.tick(1.0) { TickMsg.new(time: Time.now) })
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
          # Runtime state changed — triggers re-render via Bubbletea
          Bubbletea.none
        else
          Bubbletea.none
        end
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

      def input_focused? = @input_focused
      def scrolled_up? = @scrolled_up
      def spinner_view = @spinner.view

      private

      def handle_key(msg)
        key = msg.to_s

        case key
        when "ctrl+c", "ctrl+d"
          save_state
          return Bubbletea.quit
        when "enter"
          return submit_input
        when "pgup"
          @chat_viewport.page_up
          @scrolled_up = true
          return Bubbletea.none
        when "pgdown"
          @chat_viewport.page_down
          @scrolled_up = @chat_viewport.at_bottom? ? false : true
          return Bubbletea.none
        when "backspace"
          @input_text = @input_text[0..-2] if @input_text.length > 0
          return Bubbletea.none
        end

        # Regular character input
        if key.length == 1 && key.ord >= 32
          @input_text << key
        end
        Bubbletea.none
      end

      def submit_input
        text = @input_text.strip
        @input_text = ""
        return Bubbletea.none if text.empty?

        # Busy guard — prevent concurrent LLM executions
        if @executor.running? && !text.start_with?("/") && !text.start_with?("!") && !text.match?(/\A(exit|quit|bye|q)\z/i)
          @chat_history << { role: :system, content: "Agent is busy — please wait for the current execution to finish." }
          return Bubbletea.none
        end

        # Exit
        if text.match?(/\A(exit|quit|bye|q)\z/i)
          save_state
          return Bubbletea.quit
        end

        @chat_history << { role: :user, content: text }
        @scrolled_up = false

        if text.start_with?("/")
          handle_slash(text)
        elsif text.start_with?("!")
          handle_ruby(text[1..].strip)
        elsif ruby_syntax?(text)
          handle_ruby_or_llm(text)
        else
          handle_llm(text)
        end
      end

      def handle_slash(text)
        cmd, *args = text.sub(/\A\//, "").split(" ", 2)
        arg = args.first

        if cmd == "plan"
          @mode = @mode == :plan ? :normal : :plan
          @chat_history << { role: :system, content: "mode: #{@mode}" }
          return Bubbletea.none
        end

        # Object explorer commands
        case cmd
        when "ls"
          result = ObjectExplorer.ls(@caller_binding)
          if result[:type] == :data
            lines = result[:data].flat_map { |section, items| ["#{section}:", *items] }
            @chat_history << { role: :system, content: lines.join("\n") }
          end
          return Bubbletea.none
        when "cd"
          @nav_stack ||= []
          result = ObjectExplorer.cd(arg || "..", @caller_binding, @nav_stack)
          if result[:type] == :success
            @caller_binding = result[:data][:binding]
            @chat_history << { role: :system, content: "cd → #{result[:data][:label]}" }
          else
            @chat_history << { role: :error, content: result[:message] }
          end
          return Bubbletea.none
        when "source"
          result = ObjectExplorer.source(arg.to_s, @caller_binding)
          if result[:type] == :data
            @chat_history << { role: :system, content: "#{result[:data][:file]}:#{result[:data][:line]}\n#{result[:data][:source]}" }
          else
            @chat_history << { role: :error, content: result[:message] }
          end
          return Bubbletea.none
        when "doc"
          result = ObjectExplorer.doc(arg.to_s, @caller_binding)
          @chat_history << { role: :system, content: result[:data][:doc].to_s }
          return Bubbletea.none
        when "find"
          result = ObjectExplorer.find(arg.to_s, @caller_binding)
          if result[:type] == :data
            @chat_history << { role: :system, content: result[:data][:matches].join(", ") }
          else
            @chat_history << { role: :system, content: result[:message] }
          end
          return Bubbletea.none
        when "whereami"
          result = ObjectExplorer.whereami(@caller_binding)
          d = result[:data]
          @chat_history << { role: :system, content: "#{d[:file]}:#{d[:line]} (#{d[:receiver]})" }
          return Bubbletea.none
        end

        result = Claw::Commands.dispatch(cmd, arg, runtime: @runtime)
        handle_command_result(CommandResultMsg.new(result: result, cmd: cmd))
        Bubbletea.none
      end

      def handle_ruby(code)
        eval_result = @executor.eval_ruby(code, @caller_binding)
        if eval_result[:success]
          @chat_history << { role: :ruby, content: eval_result[:result].inspect }
          # Track method definitions for session persistence
          if eval_result[:result].is_a?(Symbol) && code.strip.match?(/\Adef\s/)
            track_definition(@caller_binding, code, eval_result[:result])
          end
        else
          @chat_history << { role: :error, content: "#{eval_result[:error].class}: #{eval_result[:error].message}" }
        end
        @runtime&.resources&.dig("binding")&.scan_binding
        Bubbletea.none
      end

      def handle_ruby_or_llm(text)
        eval_result = @executor.eval_ruby(text, @caller_binding)
        if eval_result[:success]
          @chat_history << { role: :ruby, content: eval_result[:result].inspect }
          @runtime&.resources&.dig("binding")&.scan_binding
          Bubbletea.none
        elsif eval_result[:error].is_a?(NameError) && (text.include?(" ") || text.match?(/[^\x00-\x7F]/))
          handle_llm(text)
        else
          @chat_history << { role: :error, content: "#{eval_result[:error].class}: #{eval_result[:error].message}" }
          Bubbletea.none
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
        Bubbletea.none
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

      def ruby_syntax?(input)
        RubyVM::InstructionSequence.compile(input)
        true
      rescue SyntaxError
        false
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
