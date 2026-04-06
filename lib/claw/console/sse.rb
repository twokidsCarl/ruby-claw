# frozen_string_literal: true

module Claw
  module Console
    # Server-Sent Events helper for streaming events to the browser.
    module SSE
      # Stream events from the event logger to a Sinatra stream block.
      #
      # @param stream [Object] Sinatra stream object (responds to <<)
      # @param logger [EventLogger] the event source
      # @param poll_interval [Float] seconds between polls
      def self.stream_events(stream, logger, poll_interval: 0.5)
        last_timestamp = nil

        loop do
          events = logger.tail(since: last_timestamp)
          events.each do |event|
            stream << "data: #{JSON.generate(event)}\n\n"
            last_timestamp = event[:timestamp]
          end
          sleep(poll_interval)
        end
      rescue IOError
        # Client disconnected
      end
    end
  end
end
