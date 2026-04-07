# frozen_string_literal: true

module Claw
  module TUI
    # Content folding for Claude Code-style UX:
    # - Large text blocks collapsed
    # - Consecutive same-type tool calls collapsed
    # - Colored diff rendering
    module Folding
      # Fold text that exceeds a line threshold.
      #
      # @param text [String] the text to potentially fold
      # @param threshold [Integer] max lines before folding (default 10)
      # @return [Hash] { folded: bool, display: String, full: String }
      def self.fold_text(text, threshold: 10)
        lines = text.lines
        if lines.size <= threshold
          { folded: false, display: text, full: text }
        else
          preview = lines[0, 3].join
          summary = "[+#{lines.size - 3} more lines · Ctrl+E to expand]"
          display = "#{preview}#{Styles::TOOL_STYLE.render(summary)}"
          { folded: true, display: display, full: text }
        end
      end

      # Fold consecutive same-type tool calls into a summary.
      #
      # @param calls [Array<Hash>] tool call messages ({ role: :tool_call, ... })
      # @return [Array<Hash>] folded messages (may be shorter)
      def self.fold_tool_calls(messages)
        return messages if messages.size <= 2

        # Only fold consecutive :tool_call messages; pass everything else through
        result = []
        tool_group = []

        flush = -> {
          if tool_group.size > 2
            tool_name = tool_group.first[:detail]&.split("(")&.first || "tool"
            targets = tool_group.map { |c| c[:detail].to_s.split("(").last&.tr(")", "") || "" }
            summary = "#{tool_group.size}x #{tool_name} (#{targets.first(3).join(', ')}#{targets.size > 3 ? ', ...' : ''})"
            result << { role: :tool_call, icon: "⚡", detail: summary,
                        folded: true, children: tool_group }
          else
            result.concat(tool_group)
          end
          tool_group.clear
        }

        messages.each do |msg|
          if msg[:role] == :tool_call
            tool_group << msg
          else
            flush.call unless tool_group.empty?
            result << msg
          end
        end
        flush.call unless tool_group.empty?

        result
      end

      # Render a diff hash with colors (green for additions, red for removals).
      #
      # @param diff_text [String] unified diff text
      # @return [String] colored diff
      def self.render_diff(diff_text)
        diff_text.lines.map do |line|
          case line[0]
          when "+"
            Lipgloss::Style.new.foreground("#32CD32").render(line.rstrip)
          when "-"
            Lipgloss::Style.new.foreground("#FF4444").render(line.rstrip)
          when "~"
            Lipgloss::Style.new.foreground("#FFD700").render(line.rstrip)
          else
            line.rstrip
          end
        end.join("\n")
      end

      # Render a resource diff hash from Runtime#diff.
      #
      # @param diffs [Hash] { resource_name => diff_string }
      # @return [String] colored output
      def self.render_resource_diff(diffs)
        sections = diffs.map do |name, diff_text|
          header = Lipgloss::Style.new.bold(true).render("#{name}:")
          colored = render_diff(diff_text)
          "#{header}\n#{colored}"
        end
        sections.join("\n\n")
      end
    end
  end
end
