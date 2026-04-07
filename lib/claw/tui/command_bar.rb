# frozen_string_literal: true

module Claw
  module TUI
    # Bottom bar: slash command hints + keyboard shortcuts.
    module CommandBar
      HINTS = %w[/snapshot /rollback /diff /history /status /evolve /plan /role].freeze

      def self.render(model, width)
        left = HINTS.join("  ")
        right = "ctrl+c interrupt  ctrl+d quit"
        left_w, _ = Lipgloss.size(left)
        right_w, _ = Lipgloss.size(right)
        spacing = width - left_w - right_w - 2
        spacing = 1 if spacing < 1

        text = "#{left}#{" " * spacing}#{right}"
        Styles::COMMAND_BAR.width(width).render(text)
      end
    end
  end
end
