# frozen_string_literal: true

module Claw
  module TUI
    # Runs Mana::Engine#execute in a background thread, sending MVU messages
    # back to the model via a callback. Manages runtime state transitions.
    class AgentExecutor
      def initialize(runtime)
        @runtime = runtime
        @mutex = Mutex.new
        @running = false
      end

      # Is an LLM execution currently in progress?
      def running? = @running

      # Execute an LLM prompt in a background thread.
      # Yields MVU message objects as events occur.
      # Returns nil if already running.
      #
      # @param input [String] user prompt
      # @param binding [Binding] caller's binding
      # @return [Thread, nil] the execution thread, or nil if busy
      def execute(input, binding, &on_event)
        @mutex.synchronize do
          return nil if @running
          @running = true
        end

        @runtime&.transition!(:thinking)

        # Capture thread-local state from main thread
        parent_context = Thread.current[:mana_context]
        parent_role = Thread.current[:claw_role]
        parent_memory = Thread.current[:claw_memory]

        Thread.new do
          # Propagate thread-local state to agent thread
          Thread.current[:mana_context] = parent_context
          Thread.current[:claw_role] = parent_role
          Thread.current[:claw_memory] = parent_memory

          engine = Mana::Engine.new(binding)
          step_num = 0

          result = engine.execute(input) do |type, *args|
            case type
            when :text
              on_event.call(AgentTextMsg.new(text: args[0]))

            when :tool_start
              step_num += 1
              name, input_data = args
              @runtime&.transition!(:executing_tool,
                step: Runtime::Step.new(
                  number: step_num,
                  tool_name: name,
                  target: input_data.is_a?(Hash) ? (input_data[:name] || input_data["name"] || name) : name
                ))
              on_event.call(ToolCallMsg.new(name: name, input: input_data))

            when :tool_end
              name, result_str = args
              on_event.call(ToolResultMsg.new(name: name, result: result_str))
              @runtime&.transition!(:thinking)
            end
          end

          @runtime&.transition!(:idle)
          on_event.call(ExecutionDoneMsg.new(result: result, trace: engine.trace_data))
        rescue => e
          @runtime&.transition!(:failed)
          on_event.call(ExecutionErrorMsg.new(error: e))
        ensure
          @mutex.synchronize { @running = false }
        end
      end

      # Execute a Ruby expression, returning the result or error.
      #
      # @param code [String] Ruby code to eval
      # @param binding [Binding] caller's binding
      # @return [Hash] { success: bool, result: Any, error: Exception? }
      def eval_ruby(code, binding)
        result = binding.eval(code)
        { success: true, result: result }
      rescue => e
        { success: false, error: e }
      end
    end
  end
end
