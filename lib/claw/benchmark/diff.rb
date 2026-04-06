# frozen_string_literal: true

module Claw
  module Benchmark
    # Compare two benchmark reports.
    module Diff
      # Compare two report files.
      #
      # @param path_a [String] path to report A
      # @param path_b [String] path to report B
      # @return [String] comparison output
      def self.compare(path_a, path_b)
        raise "Report not found: #{path_a}" unless File.exist?(path_a)
        raise "Report not found: #{path_b}" unless File.exist?(path_b)

        scores_a = extract_scores(File.read(path_a))
        scores_b = extract_scores(File.read(path_b))

        all_tasks = (scores_a.keys + scores_b.keys).uniq.sort

        lines = ["# Benchmark Diff\n"]
        lines << "**A:** #{File.basename(path_a)}"
        lines << "**B:** #{File.basename(path_b)}"
        lines << ""

        # Suite score comparison
        suite_a = scores_a.values.sum / [scores_a.size, 1].max.to_f
        suite_b = scores_b.values.sum / [scores_b.size, 1].max.to_f
        delta = suite_b - suite_a
        indicator = delta > 0 ? "↑" : delta < 0 ? "↓" : "="
        lines << "**Suite score:** #{suite_a.round(1)} → #{suite_b.round(1)} (#{indicator} #{delta.abs.round(1)})"
        lines << ""

        # Per-task changes
        lines << "| Task | A | B | Delta |"
        lines << "|------|---|---|-------|"
        all_tasks.each do |task|
          sa = scores_a[task] || 0
          sb = scores_b[task] || 0
          d = sb - sa
          sign = d > 0 ? "+" : ""
          lines << "| #{task} | #{sa.round(1)} | #{sb.round(1)} | #{sign}#{d.round(1)} |"
        end

        lines.join("\n")
      end

      # Extract task scores from a report Markdown file.
      # Looks for lines like "### task_id (...)" followed by "- **Score:** N"
      def self.extract_scores(text)
        scores = {}
        current_task = nil

        text.each_line do |line|
          if line.match?(/^### (\S+)/)
            current_task = line.match(/^### (\S+)/)[1]
          elsif current_task && line.match?(/\*\*Score:\*\*\s*([\d.]+)/)
            scores[current_task] = line.match(/\*\*Score:\*\*\s*([\d.]+)/)[1].to_f
            current_task = nil
          end
        end

        scores
      end

      private_class_method :extract_scores
    end
  end
end
