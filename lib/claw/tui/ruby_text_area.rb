# frozen_string_literal: true

module Claw
  module TUI
    # TextArea subclass with Ruby syntax highlighting.
    # Overrides render_text to apply ANSI color codes per token.
    class RubyTextArea < Bubbles::TextArea
      private

      def render_text(text)
        return text if text.empty?
        InputHandler.highlight(text)
      end
    end
  end
end
