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
        ta.width = width - 4
        # Dynamic height: expand to actual line count, cap at 5
        line_count = [ta.line_count, 1].max
        ta.height = [line_count, 5].min
        input_view = ta.view
        _, input_h = Lipgloss.size(input_view)
        input_h = [input_h, 5].min

        # Chat viewport fills remaining space
        chat_height = height - input_h - 1
        chat_height = 3 if chat_height < 3

        # Render chat messages
        content = render_messages(model.chat_history, width - 4)

        # Set up viewport
        viewport = model.chat_viewport
        viewport.width = width - 4
        viewport.height = chat_height
        viewport.content = content
        viewport.goto_bottom unless model.scrolled_up?

        # Compose with border
        chat_view = viewport.view
        panel = "#{chat_view}\n#{input_view}"

        Styles::PANEL_BORDER.width(width).height(height).render(panel)
      end

      def self.render_messages(messages, width)
        # Fold consecutive tool calls
        messages = Folding.fold_tool_calls(messages)

        lines = []
        messages.each do |msg|
          case msg[:role]
          when :user
            lines << Styles::USER_STYLE.render(">> #{msg[:content]}")
          when :agent
            rendered = begin
              Glamour.render(msg[:content].to_s)
            rescue
              msg[:content].to_s
            end
            folded = Folding.fold_text(rendered.rstrip)
            lines << Styles::AGENT_STYLE.render("claw> ") + folded[:display]
          when :tool_call
            lines << Styles::TOOL_STYLE.render("  #{msg[:icon] || "⚡"} #{msg[:detail]}")
          when :tool_result
            lines << Styles::RESULT_STYLE.render("  ↩ #{truncate(msg[:result].to_s, width - 6)}")
          when :ruby
            highlighted = InputHandler.highlight(msg[:content].to_s)
            lines << Styles::RUBY_STYLE.render("=> #{highlighted}")
          when :error
            lines << Styles::ERROR_STYLE.render("error: #{msg[:content]}")
          when :system
            lines << Styles::TOOL_STYLE.render("  #{msg[:content]}")
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
