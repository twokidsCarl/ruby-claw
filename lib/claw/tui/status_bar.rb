# frozen_string_literal: true

module Claw
  module TUI
    # Top status bar: version | model | snapshot id | token usage | state
    # Dynamically drops lower-priority items when viewport is too narrow.
    module StatusBar
      def self.render(model, width)
        right = build_right(model, width)

        # Left items in priority order (last dropped first)
        left_items = [
          "claw v#{Claw::VERSION} b#{Claw::BUILD.split('-').last}",
          Mana.config.model.to_s,
          "snap:#{model.last_snapshot_id}",
          model.token_display
        ]

        # Drop items from the end until it fits in one line
        text = nil
        loop do
          left_text = left_items.join(" | ")
          text = compose(left_text, right, width)
          break if visible_width(text) <= width || left_items.size <= 1
          left_items.pop
        end

        Styles::STATUS_BAR.width(width).render(text)
      end

      def self.build_right(model, width)
        parts = []
        parts << "↑pgup ↓pgdn" if model.scrolled_up?
        parts << "mode: #{model.mode}" if model.mode != :normal

        state = model.runtime&.state
        case state
        when :thinking
          parts << "#{model.spinner_view} thinking..."
        when :executing_tool
          step = model.runtime&.current_step
          parts << (step ? "#{model.spinner_view} #{step.tool_name}" : "#{model.spinner_view} exec...")
        end

        parts.join(" | ")
      end

      def self.compose(left, right, width)
        return left if right.empty?
        gap = width - visible_width(left) - visible_width(right) - 2
        gap > 0 ? "#{left}#{" " * gap}#{right}" : "#{left} #{right}"
      end

      def self.visible_width(str)
        # Strip ANSI escape sequences for width calculation
        str.gsub(/\e\[[0-9;]*m/, "").size
      end

      private_class_method :build_right, :compose, :visible_width
    end
  end
end
