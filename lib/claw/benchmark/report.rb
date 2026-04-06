# frozen_string_literal: true

require "fileutils"

module Claw
  module Benchmark
    # Generate Markdown benchmark reports.
    module Report
      # Generate a full report from suite results.
      #
      # @param suite [SuiteResult]
      # @return [String] Markdown report
      def self.generate(suite)
        lines = ["# Benchmark Report\n"]
        lines << "**Date:** #{suite.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
        lines << ""

        # Summary
        lines << "## Summary"
        lines << ""
        total = suite.results.size
        passed = suite.results.count { |r| r.pass_rate == 1.0 }
        lines << "| Metric | Value |"
        lines << "|--------|-------|"
        lines << "| Total tasks | #{total} |"
        lines << "| Suite score | #{suite.suite_score.round(1)} |"
        lines << "| Pass rate | #{(suite.pass_rate * 100).round(1)}% |"
        lines << "| All-pass tasks | #{passed}/#{total} |"
        lines << ""

        # By Layer
        lines << "## By Layer"
        lines << ""
        layers = suite.results.group_by { |r| r.task.layer }
        lines << "| Layer | Tasks | Pass Rate | Avg Score |"
        lines << "|-------|-------|-----------|-----------|"
        layers.each do |layer, results|
          pr = results.sum(&:pass_rate) / results.size * 100
          sc = results.sum(&:avg_score) / results.size
          lines << "| #{layer} | #{results.size} | #{pr.round(1)}% | #{sc.round(1)} |"
        end
        lines << ""

        # Task Details
        lines << "## Task Details"
        lines << ""
        suite.results.each do |tr|
          lines << "### #{tr.task.id} (#{tr.task.layer})"
          lines << ""
          lines << "- **Score:** #{tr.avg_score.round(1)}"
          lines << "- **Pass rate:** #{(tr.pass_rate * 100).round(0)}%"
          lines << ""
          lines << "| Run | Correct | Rounds | Tokens | Time (ms) | Path |"
          lines << "|-----|---------|--------|--------|-----------|------|"
          tr.runs.each_with_index do |run, i|
            path = (run.tool_path || []).join(" → ")
            mark = run.correct ? "✓" : "✗"
            lines << "| #{i + 1} | #{mark} | #{run.rounds} | #{run.tokens} | #{run.elapsed_ms} | #{path} |"
          end
          if tr.runs.any? { |r| r.error }
            lines << ""
            tr.runs.each_with_index do |run, i|
              lines << "- Run #{i + 1} error: #{run.error}" if run.error
            end
          end
          lines << ""
        end

        lines.join("\n")
      end

      # Save report to .ruby-claw/benchmarks/
      #
      # @param report_text [String] Markdown content
      # @param claw_dir [String] path to .ruby-claw/
      # @return [String] file path
      def self.save(report_text, claw_dir = ".ruby-claw")
        dir = File.join(claw_dir, "benchmarks")
        FileUtils.mkdir_p(dir)
        filename = "#{Time.now.strftime('%Y-%m-%d_%H%M%S')}.md"
        path = File.join(dir, filename)
        File.write(path, report_text)
        path
      end
    end
  end
end
