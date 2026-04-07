# frozen_string_literal: true

require "lipgloss"

module Claw
  module TUI
    # Centralized color and style definitions for the TUI.
    module Styles
      # Colors
      CYAN       = "#00BFFF"
      YELLOW     = "#FFD700"
      GREEN      = "#32CD32"
      RED        = "#FF4444"
      MAGENTA    = "#FF69B4"
      DIM_GRAY   = "#666666"
      BORDER     = "#444444"
      BG_DARK    = "#1A1A2E"

      # Status bar (top) — reversed colors for visibility on any terminal bg
      STATUS_BAR = Lipgloss::Style.new
        .foreground("#000000")
        .background(CYAN)
        .bold(true)
        .padding(0, 1)

      # Chat panel styles
      USER_STYLE = Lipgloss::Style.new.foreground(CYAN).bold(true)
      AGENT_STYLE = Lipgloss::Style.new.foreground(YELLOW)
      TOOL_STYLE = Lipgloss::Style.new.foreground("#888888")
      RESULT_STYLE = Lipgloss::Style.new.foreground(GREEN)
      ERROR_STYLE = Lipgloss::Style.new.foreground(RED)
      RUBY_STYLE = Lipgloss::Style.new.foreground(MAGENTA)

      # Panel borders
      PANEL_BORDER = Lipgloss::Style.new
        .border(:rounded)
        .border_foreground(BORDER)
        .padding(0, 1)

      # Right panel section headers
      SECTION_HEADER = Lipgloss::Style.new
        .foreground(CYAN)
        .bold(true)

      # Command bar (bottom)
      COMMAND_BAR = Lipgloss::Style.new
        .foreground(DIM_GRAY)
        .padding(0, 1)

      # Spinner style
      SPINNER_STYLE = Lipgloss::Style.new.foreground(YELLOW)

      # Progress bar colors
      PROGRESS_FULL = GREEN
      PROGRESS_EMPTY = DIM_GRAY
    end
  end
end
