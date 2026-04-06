# frozen_string_literal: true

require "glamour"

module Claw
  module TUI
    # Left panel: chat history + input box.
    # Uses Bubbles::Viewport for scrollable content and Glamour for markdown rendering.
    module ChatPanel
      def self.render(model, width, height)
        # Reserve 3 lines for input box
        chat_height = height - 3

        # Render chat messages
        content = render_messages(model.chat_history, width - 4)

        # Set up viewport
        viewport = model.chat_viewport
        viewport.width = width - 4
        viewport.height = chat_height
        viewport.content = content
        viewport.goto_bottom unless model.scrolled_up?

        # Input box
        input_line = render_input(model, width - 4)

        # Compose with border
        chat_view = viewport.view
        panel = "#{chat_view}\n#{input_line}"

        Styles::PANEL_BORDER.width(width).height(height).render(panel)
      end

      def self.render_messages(messages, width)
        # Fold consecutive tool calls
        messages = Folding.fold_tool_calls(messages)

        lines = []
        messages.each do |msg|
          case msg[:role]
          when :user
            lines << Styles::USER_STYLE.render("you> #{msg[:content]}")
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

      def self.render_input(model, width)
        prompt = model.mode == :plan ? "plan> " : "claw> "
        cursor = model.input_focused? ? "█" : ""
        text = "#{prompt}#{model.input_text}#{cursor}"
        Lipgloss::Style.new.foreground(Styles::CYAN).width(width).render(text)
      end

      def self.truncate(str, max)
        str.length > max ? "#{str[0, max - 3]}..." : str
      end

      private_class_method :render_messages, :render_input, :truncate
    end
  end
end
