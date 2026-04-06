# frozen_string_literal: true

module Claw
  module Benchmark
    # A single benchmark task definition.
    Task = Struct.new(
      :id,          # unique task identifier (String)
      :layer,       # :mana, :claw, :runtime, :evolution
      :setup,       # Proc → Hash of variables to inject into binding
      :prompt,      # String prompt to send to the engine
      :expect,      # Proc(binding) → boolean (correctness check)
      :max_rounds,  # maximum allowed LLM iterations
      :max_tokens,  # maximum allowed token usage
      :ideal_path,  # Array<String> of expected tool call sequence
      keyword_init: true
    )

    # Result of a single run (one of 3 per task).
    RunResult = Struct.new(
      :correct,     # boolean
      :rounds,      # actual LLM iterations
      :tokens,      # actual token usage (input + output)
      :tool_path,   # Array<String> actual tool call sequence
      :elapsed_ms,  # execution time in milliseconds
      :error,       # exception message if failed, nil otherwise
      keyword_init: true
    )

    # Aggregated result for one task across multiple runs.
    TaskResult = Struct.new(
      :task,        # Task instance
      :runs,        # Array<RunResult>
      keyword_init: true
    ) do
      def pass_rate
        return 0.0 if runs.empty?
        runs.count(&:correct).to_f / runs.size
      end

      def avg_score
        scores = runs.map { |r| Scorer.score_run(r, task) }
        scores.sum / scores.size.to_f
      end
    end

    # Suite-level result across all tasks.
    SuiteResult = Struct.new(
      :results,     # Array<TaskResult>
      :timestamp,   # Time
      keyword_init: true
    ) do
      def suite_score
        return 0.0 if results.empty?
        results.sum(&:avg_score) / results.size.to_f
      end

      def pass_rate
        return 0.0 if results.empty?
        results.sum(&:pass_rate) / results.size.to_f
      end
    end
  end
end
