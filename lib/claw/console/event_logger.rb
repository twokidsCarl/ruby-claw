# frozen_string_literal: true

require "json"
require "fileutils"

module Claw
  module Console
    # Writes structured JSONL events to .ruby-claw/log/events.jsonl.
    # Used by the console for real-time observability.
    # Events are opt-in — silently dropped if log directory doesn't exist.
    class EventLogger
      attr_reader :log_path

      def initialize(log_dir)
        @log_dir = log_dir
        @log_path = File.join(log_dir, "events.jsonl") if log_dir
        @mutex = Mutex.new
      end

      # Emit a structured event.
      #
      # @param type [String] event type (e.g., "llm_call_start", "tool_call")
      # @param data [Hash] event-specific data
      def emit(type:, data: {})
        return unless @log_dir && Dir.exist?(@log_dir)

        event = {
          timestamp: Time.now.iso8601(3),
          type: type,
          data: data
        }

        @mutex.synchronize do
          File.open(@log_path, "a") { |f| f.puts(JSON.generate(event)) }
        end
      rescue => e
        # Silently drop events on error
      end

      # Read events since a given timestamp.
      #
      # @param since [String, nil] ISO 8601 timestamp (nil = all events)
      # @return [Array<Hash>] events
      def tail(since: nil)
        return [] unless @log_path && File.exist?(@log_path)

        events = []
        File.foreach(@log_path) do |line|
          event = JSON.parse(line.strip, symbolize_names: true) rescue next
          if since.nil? || event[:timestamp] > since
            events << event
          end
        end
        events
      end

      # Total event count.
      def count
        return 0 unless @log_path && File.exist?(@log_path)
        File.foreach(@log_path).count
      end

      # Clear all events.
      def clear!
        File.write(@log_path, "") if @log_path && File.exist?(@log_path)
      end
    end
  end
end
