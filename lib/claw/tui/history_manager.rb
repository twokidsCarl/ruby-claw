# frozen_string_literal: true

module Claw
  module TUI
    # Owns the shell-style command-line history for the TUI input.
    #
    # Previously these three pieces of state lived as instance variables on
    # Model (@input_history, @history_index, @saved_input) and the up/down
    # navigation logic was an inline private method. Pulling them into a
    # dedicated object makes the contract obvious:
    #
    #   - `record(line)` appends a submitted line to history.
    #   - `up(current_text)` recalls the previous entry; pass the current
    #     textarea content so down() can restore unsaved typing.
    #   - `down` advances forward, returning the saved buffer when the
    #     navigation cursor falls off the end.
    #
    # Returns the string to load into the textarea (or nil to do nothing).
    # All textarea mutation stays in Model — this class is pure state.
    class HistoryManager
      def initialize
        @entries = []
        @index = nil      # nil = not navigating; integer = position in @entries
        @saved = +""      # the text the user had typed before pressing up the first time
      end

      def empty?
        @entries.empty?
      end

      def size
        @entries.size
      end

      # Append a freshly submitted line. Resets the navigation cursor so the
      # next "up" starts from the most recent entry.
      def record(line)
        @entries << line.to_s unless line.to_s.empty?
        @index = nil
        @saved = +""
      end

      # Navigate to the previous (older) entry. `current_text` is the
      # textarea's current content, saved on the FIRST up press so a later
      # down can restore unsaved typing.
      # Returns the string to load, or nil if there's nothing to recall.
      def up(current_text)
        return nil if @entries.empty?

        if @index.nil?
          @saved = current_text.to_s
          @index = @entries.size - 1
        elsif @index > 0
          @index -= 1
        else
          # Already at the oldest entry — nothing to recall
          return nil
        end

        @entries[@index]
      end

      # Navigate to the next (newer) entry, or restore the saved buffer when
      # falling off the end. Returns nil if not currently navigating.
      def down
        return nil if @index.nil?

        if @index < @entries.size - 1
          @index += 1
          @entries[@index]
        else
          @index = nil
          @saved
        end
      end

      # Test/debug accessors — not part of the normal interface
      attr_reader :entries
    end
  end
end
