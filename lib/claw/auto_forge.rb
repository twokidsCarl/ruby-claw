# frozen_string_literal: true

module Claw
  # Detects repeated eval patterns in traces and suggests tool promotion.
  module AutoForge
    THRESHOLD = 3 # Minimum occurrences before suggesting

    class << self
      # Analyze recent traces for repeated eval patterns.
      #
      # @param traces_dir [String] path to .ruby-claw/traces/
      # @param limit [Integer] number of recent traces to analyze
      # @return [Array<Hash>] suggestions [{method_name:, occurrences:, sample_code:}]
      def analyze(traces_dir, limit: 10)
        return [] unless traces_dir && Dir.exist?(traces_dir)

        files = Dir.glob(File.join(traces_dir, "*.md")).sort.last(limit)
        return [] if files.empty?

        # Collect all eval tool calls that define methods
        method_counts = Hash.new { |h, k| h[k] = { count: 0, sample: nil } }

        files.each do |file|
          content = File.read(file)
          # Look for eval tool calls containing method definitions
          content.scan(/eval.*?```ruby\s*\n(.*?)```/m).each do |match|
            code = match[0]
            # Extract method name from `def method_name`
            code.scan(/\bdef\s+(\w+)/).each do |name_match|
              name = name_match[0]
              method_counts[name][:count] += 1
              method_counts[name][:sample] ||= code.strip
            end
          end
        end

        method_counts
          .select { |_, v| v[:count] >= THRESHOLD }
          .map { |name, v| { method_name: name, occurrences: v[:count], sample_code: v[:sample] } }
          .sort_by { |s| -s[:occurrences] }
      end

      # Quick check: are there any suggestions?
      #
      # @param traces_dir [String]
      # @return [Boolean]
      def suggest?(traces_dir)
        !analyze(traces_dir).empty?
      end

      # Format suggestions for display.
      #
      # @param suggestions [Array<Hash>]
      # @return [String]
      def format_suggestions(suggestions)
        return "" if suggestions.empty?

        lines = ["Detected repeated method patterns — consider promoting to tools:"]
        suggestions.each do |s|
          lines << "  · #{s[:method_name]} (#{s[:occurrences]}x) — /forge #{s[:method_name]}"
        end
        lines.join("\n")
      end
    end
  end
end
