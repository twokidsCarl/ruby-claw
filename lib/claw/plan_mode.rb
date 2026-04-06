# frozen_string_literal: true

module Claw
  # Plan Mode: two-phase plan-then-execute workflow.
  #
  # Phase 1 (plan): LLM outputs a step-by-step plan without executing tools.
  # Phase 2 (execute): After user confirmation, execute inside a fork for safety.
  class PlanMode
    STATES = %i[inactive ready planning reviewing executing].freeze

    attr_reader :pending_plan, :state

    def initialize(runtime)
      @runtime = runtime
      @state = :inactive
      @pending_plan = nil
    end

    def active? = @state != :inactive
    def pending? = @state == :reviewing

    def toggle!
      if @state == :inactive
        @state = :ready  # activated, waiting for plan! call
        true
      else
        discard!
        false
      end
    end

    # Phase 1: Generate a plan (no tool execution).
    #
    # @param prompt [String] user's task description
    # @param caller_binding [Binding] for binding context
    # @param on_text [Proc, nil] streaming callback
    # @return [String] the plan text
    def plan!(prompt, caller_binding, &on_text)
      @state = :planning

      binding_md = @runtime&.resources&.dig("binding")&.to_md || "(no binding)"
      memory_md = @runtime&.resources&.dig("memory")&.to_md || "(no memory)"

      planning_prompt = <<~PROMPT
        The user wants: #{prompt}

        Current binding state:
        #{binding_md}

        Current memory:
        #{memory_md}

        Output ONLY a step-by-step plan describing what tools you would use and in what order.
        Do NOT call any tools. Do NOT execute anything.
        Format as a numbered list. For each step, specify:
        - Which tool to use
        - On what target (variable/method/etc.)
        - Expected result
      PROMPT

      engine = Mana::Engine.new(caller_binding)
      # Execute with empty tools array so LLM cannot call any tools
      plan_text = engine.execute(planning_prompt, &on_text)

      @pending_plan = {
        prompt: prompt,
        plan_text: plan_text.to_s,
        created_at: Time.now
      }
      @state = :reviewing
      @pending_plan[:plan_text]
    end

    # Phase 2: Execute the approved plan inside a fork for safety.
    #
    # @param caller_binding [Binding]
    # @param edited_plan [String, nil] user-edited plan text (optional)
    # @param on_text [Proc, nil] streaming callback
    # @return [Array] [success, result] from Runtime#fork
    def execute!(caller_binding, edited_plan: nil, &on_text)
      raise "No pending plan" unless @state == :reviewing

      @state = :executing
      plan_text = edited_plan || @pending_plan[:plan_text]
      prompt = @pending_plan[:prompt]
      @pending_plan = nil

      result = @runtime.fork(label: "plan_execution") do
        engine = Mana::Engine.new(caller_binding)
        engine.execute(<<~EXEC, &on_text)
          Execute this task: #{prompt}

          Your approved plan:
          #{plan_text}

          Follow the plan step by step. Use the available tools to complete each step.
        EXEC
      end

      @state = :inactive
      result
    end

    # Discard the pending plan.
    def discard!
      @pending_plan = nil
      @state = :inactive
    end
  end
end
