# frozen_string_literal: true

require "glamour"

module Claw
  module TUI
    # Left panel: chat history + input box.
    # Uses Bubbles::Viewport for scrollable content and Glamour for markdown rendering.
    module ChatPanel
      def self.render(model, width, height)
        # Configure textarea width and render it
        ta = model.textarea
        ta.width = width - 2
        # Dynamic height: expand to actual line count, cap at 5
        line_count = [ta.line_count, 1].max
        ta.height = [line_count, 5].min
        # Recalculate viewport offset with new height (stale from previous render cycle)
        ta.instance_variable_set(:@viewport_offset, [ta.row - ta.height + 1, 0].max)
        # Show line numbers in multi-line mode for visual clarity
        ta.show_line_numbers = line_count > 1
        input_view = ta.view
        _, input_h = Lipgloss.size(input_view)
        input_h = [input_h, 5].min

        # Chat viewport fills remaining space
        chat_height = height - input_h
        chat_height = 3 if chat_height < 3

        # Render chat messages
        content = render_messages(model.chat_history, width - 2, zone: model.zone)

        # Set up viewport
        viewport = model.chat_viewport
        viewport.width = width - 2
        viewport.height = chat_height
        viewport.content = content
        viewport.goto_bottom unless model.scrolled_up?

        # Compose with border
        chat_view = viewport.view
        panel = "#{chat_view}\n#{input_view}"

        Styles::PANEL_BORDER.width(width).height(height).render(panel)
      end

      def self.render_messages(messages, width, zone: nil)
        # Fold consecutive tool calls
        messages = Folding.fold_tool_calls(messages)

        lines = []
        messages.each_with_index do |msg, idx|
          case msg[:role]
          when :user
            lines << Styles::USER_STYLE.render(">> #{msg[:content]}")
          when :agent
            rendered = begin
              Glamour.render(msg[:content].to_s)
            rescue
              msg[:content].to_s
            end
            folded = Folding.fold_text(rendered.rstrip, zone: zone, fold_id: idx)
            if folded[:folded]
              msg[:folded_full] = folded[:full]
            end
            lines << Styles::AGENT_STYLE.render("claw> ") + folded[:display]
          when :tool_call
            lines << Styles::TOOL_STYLE.render("  #{msg[:icon] || "⚡"} #{msg[:detail]}")
          when :tool_result
            # When the result is large, the user used to see a bare `...` with
            # no indicator. Surface that data was cut, and stash the full
            # content in :folded_full so the existing fold-expand UI (Ctrl+E
            # on a focused message) can show it.
            full = msg[:result].to_s
            max = width - 6
            if full.length > max
              msg[:folded_full] = full
              shown = "#{full[0, max - 30]}... (truncated, Ctrl+E to expand)"
              lines << Styles::RESULT_STYLE.render("  ↩ #{shown}")
            else
              lines << Styles::RESULT_STYLE.render("  ↩ #{full}")
            end
          when :ruby
            highlighted = InputHandler.highlight(msg[:content].to_s)
            lines << Styles::RUBY_STYLE.render("=> #{highlighted}")
          when :error
            lines << Styles::ERROR_STYLE.render("error: #{msg[:content]}")
          when :system
            indented = msg[:content].to_s.gsub(/^/, "  ")
            lines << Styles::TOOL_STYLE.render(indented)
          end
        end
        lines.join("\n")
      end

      def self.truncate(str, max)
        str.length > max ? "#{str[0, max - 3]}..." : str
      end

      private_class_method :render_messages, :truncate
    end
  end
end
