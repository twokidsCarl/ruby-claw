# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::HistoryManager do
  subject(:history) { described_class.new }

  describe "#empty?" do
    it "starts empty" do
      expect(history.empty?).to be true
    end

    it "is non-empty after recording" do
      history.record("ls")
      expect(history.empty?).to be false
    end
  end

  describe "#record" do
    it "appends the line" do
      history.record("a")
      history.record("b")
      expect(history.entries).to eq(%w[a b])
    end

    it "ignores empty lines" do
      history.record("")
      history.record(nil)
      expect(history.entries).to be_empty
    end

    it "resets navigation state" do
      history.record("a")
      history.up("")
      history.record("b")
      # After record, up should start from the newest (b), not where we were
      expect(history.up("typed")).to eq("b")
    end
  end

  describe "#up" do
    before do
      history.record("first")
      history.record("second")
      history.record("third")
    end

    it "saves the current typed text on first press" do
      history.up("typing this")
      history.down # navigate off the end — should restore saved
      history.down
      # After exhausting forward, we get back the saved buffer.
      # First down → "third", second down → restore
      # Reset and try again
      h = described_class.new
      h.record("first")
      h.up("in-progress")
      # off-the-end: down should restore "in-progress"
      expect(h.down).to eq("in-progress")
    end

    it "recalls entries newest → oldest" do
      expect(history.up("")).to eq("third")
      expect(history.up("")).to eq("second")
      expect(history.up("")).to eq("first")
    end

    it "returns nil when already at the oldest entry" do
      3.times { history.up("") }
      expect(history.up("")).to be_nil
    end

    it "returns nil on an empty history" do
      h = described_class.new
      expect(h.up("anything")).to be_nil
    end
  end

  describe "#down" do
    before do
      history.record("a")
      history.record("b")
    end

    it "returns nil when not navigating" do
      expect(history.down).to be_nil
    end

    it "advances toward newer entries after up" do
      history.up("typed")  # cursor → "b"
      history.up("typed")  # cursor → "a"
      expect(history.down).to eq("b")
    end

    it "restores the saved buffer when falling off the end" do
      history.up("typed")  # cursor → "b"
      expect(history.down).to eq("typed")
    end

    it "saved buffer becomes empty after a record" do
      history.up("typed")
      history.record("c")
      # After record, navigation is reset. down should return nil since we're
      # not navigating anymore.
      expect(history.down).to be_nil
    end
  end
end
