# frozen_string_literal: true

module Claw
  module TUI
    # TextArea subclass with Ruby syntax highlighting + safe public helpers
    # for the auto-indent/auto-dedent logic that lives in Model#handle_key.
    #
    # Previously the model reached into the parent class's private state with
    # instance_variable_get(:@lines) / instance_variable_set(:@col, ...). That
    # was fragile — any Bubbles upgrade that renamed those instance variables
    # would have silently broken auto-indent without raising. By exposing the
    # mutations as named methods here, the brittle coupling is contained to a
    # single file: if Bubbles changes its internals, only RubyTextArea needs
    # to be updated, and callers stay clean.
    class RubyTextArea < Bubbles::TextArea
      # Insert `spaces` at the start of the current row, then move the cursor
      # to column `spaces.size`. Used by auto-indent after Enter.
      def indent_current_line(spaces)
        lines = instance_variable_get(:@lines)
        return if lines.nil?
        row = self.row
        lines[row] = spaces + lines[row].to_s
        instance_variable_set(:@col, spaces.size)
      end

      # Strip a leading 2-space block from the current line if present, and
      # back the cursor up by that amount. Used by auto-dedent after "end".
      # Returns true if a dedent happened, false otherwise.
      def dedent_current_line(width = 2)
        lines = instance_variable_get(:@lines)
        return false if lines.nil?
        row = self.row
        current = lines[row].to_s
        stripped = current.sub(/\A {#{width}}/, "")
        return false if stripped == current
        lines[row] = stripped
        instance_variable_set(:@col, [col - width, 0].max)
        true
      end

      # Whether the current line consists of whitespace followed by exactly
      # "end" (with optional trailing whitespace). Auto-dedent trigger.
      def current_line_is_lone_end?
        lines = instance_variable_get(:@lines)
        return false if lines.nil?
        lines[row].to_s.match?(/\A\s+end\s*\z/)
      end

      private

      def render_text(text)
        return text if text.empty?
        InputHandler.highlight(text)
      end
    end
  end
end
