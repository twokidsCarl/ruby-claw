# frozen_string_literal: true

module Claw
  module TUI
    # Top status bar: version | model | snapshot id | token usage | mode
    module StatusBar
      def self.render(model, width)
        parts = []
        parts << "ruby-claw v#{Claw::VERSION}"
        parts << Mana.config.model
        parts << "snap: ##{model.last_snapshot_id}"
        parts << "#{model.token_display}"
        parts << "mode: #{model.mode}" if model.mode != :normal

        state = model.runtime&.state
        case state
        when :thinking
          parts << "#{model.spinner_view} thinking..."
        when :executing_tool
          step = model.runtime&.current_step
          label = step ? "#{model.spinner_view} #{step.tool_name}" : "#{model.spinner_view} executing..."
          parts << label
        end

        text = parts.join(" | ")
        Styles::STATUS_BAR.width(width).render(text)
      end
    end
  end
end
