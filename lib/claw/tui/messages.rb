# frozen_string_literal: true

module Claw
  module TUI
    # MVU message types sent between components and the model.

    # Agent emitted a text chunk (streaming).
    AgentTextMsg = Struct.new(:text, keyword_init: true)

    # Agent started a tool call.
    ToolCallMsg = Struct.new(:name, :input, keyword_init: true)

    # Agent finished a tool call.
    ToolResultMsg = Struct.new(:name, :result, keyword_init: true)

    # Agent execution completed.
    ExecutionDoneMsg = Struct.new(:result, :trace, keyword_init: true)

    # Agent execution failed.
    ExecutionErrorMsg = Struct.new(:error, keyword_init: true)

    # Runtime state changed (idle/thinking/executing_tool/failed).
    StateChangeMsg = Struct.new(:old_state, :new_state, :step, keyword_init: true)

    # Tick for spinner/progress animations.
    TickMsg = Struct.new(:time, keyword_init: true)

    # Command result from a slash command.
    CommandResultMsg = Struct.new(:result, :cmd, keyword_init: true)
  end
end
