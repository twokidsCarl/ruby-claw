# frozen_string_literal: true

module Claw
  module Benchmark
    # Automatic evolution triggers based on benchmark results.
    # Event-driven: checks after each benchmark run or trace write.
    class Trigger
      def initialize(runtime:, claw_dir: ".ruby-claw")
        @runtime = runtime
        @claw_dir = claw_dir
        @mutex = Mutex.new
        @evolution_running = false
      end

      # Check after a benchmark run completes.
      # Triggers evolution if suite score regressed.
      #
      # @param current_score [Float] latest suite score
      # @param previous_score [Float, nil] previous suite score
      def check_after_benchmark!(current_score, previous_score)
        return unless previous_score
        return if current_score >= previous_score
        return if @mutex.synchronize { @evolution_running }

        trigger!(
          reason: "score_regression",
          detail: "#{previous_score.round(1)} → #{current_score.round(1)}"
        )
      end

      # Check after a trace is written.
      # Triggers evolution if the same task failed 3 consecutive times.
      #
      # @param task_id [String]
      # @param recent_results [Array<Boolean>] last N correctness results
      def check_after_trace!(task_id, recent_results)
        return if recent_results.size < 3
        return if @mutex.synchronize { @evolution_running }

        if recent_results.last(3).none?
          trigger!(
            reason: "consecutive_failures",
            detail: "#{task_id} failed 3 times in a row"
          )
        end
      end

      private

      def trigger!(reason:, detail:)
        @mutex.synchronize { @evolution_running = true }

        @runtime&.record_event(
          action: "evolution_triggered",
          target: reason,
          detail: detail
        )

        begin
          evo = Claw::Evolution.new(runtime: @runtime, claw_dir: @claw_dir)
          evo.evolve
        ensure
          @mutex.synchronize { @evolution_running = false }
        end
      end
    end
  end
end
