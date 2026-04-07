# frozen_string_literal: true

module Claw
  module TUI
    # Composes the 4-zone TUI layout: top status bar, left chat, right status, bottom commands.
    module Layout
      CHAT_RATIO = 0.70

      def self.render(model, width, height)
        # Top status bar: 1 line
        top = StatusBar.render(model, width)
        _, top_h = Lipgloss.size(top)

        # Middle area — subtract 2 extra for panel border (top + bottom lines)
        middle_h = height - top_h - 2
        middle_h = 4 if middle_h < 4

        left_w = (width * CHAT_RATIO).to_i
        right_w = width - left_w

        left = ChatPanel.render(model, left_w, middle_h)
        right = StatusPanel.render(model, right_w, middle_h)

        middle = Lipgloss.join_horizontal(Lipgloss::TOP, left, right)

        Lipgloss.join_vertical(Lipgloss::LEFT, top, middle)
      end
    end
  end
end
