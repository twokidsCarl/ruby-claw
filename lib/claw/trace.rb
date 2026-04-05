# frozen_string_literal: true

require "fileutils"

module Claw
  # Writes execution traces as Markdown files to .ruby-claw/traces/.
  # Each task execution produces one trace file with timing, token usage,
  # and tool call details per LLM iteration.
  module Trace
    TRACES_DIR = "traces"

    class << self
      # Write a trace file from engine trace_data.
      #
      # @param trace_data [Hash] from Mana::Engine#trace_data
      # @param claw_dir [String] path to .ruby-claw/ directory
      # @return [String] path to the written trace file
      def write(trace_data, claw_dir)
        dir = File.join(claw_dir, TRACES_DIR)
        FileUtils.mkdir_p(dir)

        ts = trace_data[:timestamp] || Time.now.iso8601
        filename = ts.gsub(/[:\-]/, "").sub("T", "_").split("+").first + ".md"
        path = File.join(dir, filename)

        File.write(path, render(trace_data))
        path
      end

      # Render trace_data as Markdown.
      def render(data)
        lines = []
        prompt_summary = data[:prompt].to_s
        prompt_summary = prompt_summary[0, 80] + "..." if prompt_summary.length > 80

        lines << "# Task: #{prompt_summary}"
        lines << ""
        lines << "- Started: #{data[:timestamp]}"
        lines << "- Model: #{data[:model]}"
        lines << "- Steps: #{data[:steps].size}"

        total_in = data[:steps].sum { |s| s.dig(:usage, :input_tokens) || 0 }
        total_out = data[:steps].sum { |s| s.dig(:usage, :output_tokens) || 0 }
        total_ms = data[:steps].sum { |s| s[:latency_ms] || 0 }

        lines << "- Total tokens: #{total_in} in / #{total_out} out"
        lines << "- Total latency: #{total_ms}ms"
        lines << ""

        data[:steps].each_with_index do |step, i|
          lines << "## Step #{i + 1}"
          lines << ""
          lines << "- Latency: #{step[:latency_ms]}ms"
          if step[:usage]
            lines << "- Tokens: #{step[:usage][:input_tokens] || 0} in / #{step[:usage][:output_tokens] || 0} out"
          end

          if step[:tool_calls]&.any?
            lines << ""
            lines << "### Tool calls"
            lines << ""
            step[:tool_calls].each do |tc|
              input_str = summarize_hash(tc[:input])
              result_str = truncate(tc[:result].to_s, 100)
              lines << "- **#{tc[:name]}**(#{input_str}) -> #{result_str}"
            end
          end
          lines << ""
        end

        lines.join("\n")
      end

      private

      def summarize_hash(hash)
        return "" unless hash.is_a?(Hash)
        hash.map { |k, v| "#{k}: #{truncate(v.inspect, 40)}" }.join(", ")
      end

      def truncate(str, max)
        str.length > max ? "#{str[0, max]}..." : str
      end
    end
  end
end
