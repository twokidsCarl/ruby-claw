# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Console::SSE do
  let(:log_dir) { Dir.mktmpdir("claw-sse-") }
  let(:logger) { Claw::Console::EventLogger.new(log_dir) }

  after { FileUtils.rm_rf(log_dir) }

  describe ".stream_events" do
    it "streams events as SSE data frames" do
      logger.emit(type: "test", data: { msg: "hello" })

      stream = StringIO.new
      # Run in a thread and kill after first write
      thread = Thread.new do
        described_class.stream_events(stream, logger, poll_interval: 0.05)
      end

      sleep 0.15
      thread.kill
      thread.join

      output = stream.string
      expect(output).to include("data: ")
      parsed = JSON.parse(output.lines.first.sub("data: ", "").strip)
      expect(parsed["type"]).to eq("test")
    end

    it "handles IOError from disconnected client" do
      stream = Object.new
      def stream.<<(_data)
        raise IOError, "closed stream"
      end

      logger.emit(type: "test", data: {})
      # Should not raise — IOError is rescued
      expect { described_class.stream_events(stream, logger, poll_interval: 0.01) }.not_to raise_error
    end

    it "sends no data when no events exist" do
      stream = StringIO.new

      thread = Thread.new do
        described_class.stream_events(stream, logger, poll_interval: 0.05)
      end
      sleep 0.12
      thread.kill
      thread.join

      expect(stream.string).to eq("")
    end

    it "advances timestamp to avoid re-sending events" do
      logger.emit(type: "first", data: {})
      sleep 0.01

      stream = StringIO.new
      thread = Thread.new do
        described_class.stream_events(stream, logger, poll_interval: 0.05)
      end
      sleep 0.12
      # Add another event while streaming
      logger.emit(type: "second", data: {})
      sleep 0.12
      thread.kill
      thread.join

      lines = stream.string.lines.select { |l| l.start_with?("data: ") }
      types = lines.map { |l| JSON.parse(l.sub("data: ", ""))["type"] }
      expect(types).to include("first", "second")
      # "first" should appear only once (not re-sent on next poll)
      expect(types.count("first")).to eq(1)
    end
  end
end
