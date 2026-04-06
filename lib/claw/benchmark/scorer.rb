# frozen_string_literal: true

module Claw
  module Benchmark
    # Scoring formula for benchmark runs.
    #
    # task_score = correctness * 100
    #            - (actual_rounds / max_rounds) * 20
    #            - (actual_tokens / max_tokens) * 20
    #            - path_penalty
    module Scorer
      # Score a single run against its task definition.
      #
      # @param run [RunResult]
      # @param task [Task]
      # @return [Float] score (max 100, can go negative)
      def self.score_run(run, task)
        correctness = run.correct ? 100.0 : 0.0

        rounds_penalty = task.max_rounds > 0 ?
          (run.rounds.to_f / task.max_rounds) * 20.0 : 0.0

        tokens_penalty = task.max_tokens > 0 ?
          (run.tokens.to_f / task.max_tokens) * 20.0 : 0.0

        path_pen = path_penalty(run.tool_path || [], task.ideal_path || [])

        [correctness - rounds_penalty - tokens_penalty - path_pen, 0.0].max
      end

      # Calculate path penalty using edit distance between actual and ideal tool sequences.
      #
      # @param actual [Array<String>] actual tool call sequence
      # @param ideal [Array<String>] expected tool call sequence
      # @return [Float] penalty (0 if paths match, higher for more divergence)
      def self.path_penalty(actual, ideal)
        return 0.0 if ideal.empty?

        distance = levenshtein(actual, ideal)
        # Normalize: each edit costs 5 points, max penalty 20
        [distance * 5.0, 20.0].min
      end

      # Levenshtein distance between two arrays of strings.
      def self.levenshtein(a, b)
        m = a.size
        n = b.size
        d = Array.new(m + 1) { Array.new(n + 1, 0) }

        (0..m).each { |i| d[i][0] = i }
        (0..n).each { |j| d[0][j] = j }

        (1..m).each do |i|
          (1..n).each do |j|
            cost = a[i - 1] == b[j - 1] ? 0 : 1
            d[i][j] = [
              d[i - 1][j] + 1,
              d[i][j - 1] + 1,
              d[i - 1][j - 1] + cost
            ].min
          end
        end
        d[m][n]
      end

      private_class_method :levenshtein
    end
  end
end
