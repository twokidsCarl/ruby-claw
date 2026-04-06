# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Console::EventLogger do
  let(:log_dir) { Dir.mktmpdir("claw-events-") }
  let(:logger) { described_class.new(log_dir) }

  after { FileUtils.rm_rf(log_dir) }

  describe "#emit" do
    it "writes JSONL events to log file" do
      logger.emit(type: "test_event", data: { key: "value" })

      expect(File.exist?(logger.log_path)).to be true
      line = File.readlines(logger.log_path).first
      event = JSON.parse(line, symbolize_names: true)
      expect(event[:type]).to eq("test_event")
      expect(event[:data][:key]).to eq("value")
      expect(event[:timestamp]).not_to be_nil
    end

    it "appends multiple events" do
      3.times { |i| logger.emit(type: "event_#{i}", data: {}) }
      expect(File.readlines(logger.log_path).size).to eq(3)
    end

    it "silently drops events when log dir does not exist" do
      bad_logger = described_class.new("/nonexistent/path")
      expect { bad_logger.emit(type: "test", data: {}) }.not_to raise_error
    end
  end

  describe "#tail" do
    before do
      logger.emit(type: "early", data: {})
      sleep 0.01
      @timestamp = Time.now.iso8601(3)
      sleep 0.01
      logger.emit(type: "late", data: {})
    end

    it "returns all events when since is nil" do
      events = logger.tail
      expect(events.size).to eq(2)
    end

    it "returns only events after a timestamp" do
      events = logger.tail(since: @timestamp)
      expect(events.size).to eq(1)
      expect(events.first[:type]).to eq("late")
    end
  end

  describe "#count" do
    it "returns 0 for empty log" do
      expect(logger.count).to eq(0)
    end

    it "returns correct count after events" do
      5.times { logger.emit(type: "x", data: {}) }
      expect(logger.count).to eq(5)
    end
  end

  describe "#clear!" do
    it "removes all events" do
      3.times { logger.emit(type: "x", data: {}) }
      expect(logger.count).to eq(3)
      logger.clear!
      expect(logger.count).to eq(0)
    end
  end
end
