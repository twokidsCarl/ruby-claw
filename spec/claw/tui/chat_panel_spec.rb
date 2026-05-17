# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::ChatPanel do
  describe "agent message rendering with Glamour" do
    let(:messages) { [{ role: :agent, content: "# hello\nworld" }] }
    let(:render) { described_class.send(:render_messages, messages, 70) }

    it "produces a string from a normal markdown message" do
      expect(render).to be_a(String)
      expect(render).to include("hello")
    end

    it "falls back to plain text when Glamour raises" do
      allow(Glamour).to receive(:render).and_raise(StandardError, "boom")
      out = described_class.send(:render_messages, messages, 70)
      # Plain content survives even though Glamour failed
      expect(out).to include("hello")
    end

    it "falls back with a 'glamour timed out' note when Glamour hangs" do
      # Regression: Glamour.render had no Timeout. A malformed/pathological
      # message could lock the TUI forever. Simulate hang by raising
      # Timeout::Error from Glamour.render — the chat panel catches it and
      # appends a notice instead of bubbling the exception up.
      allow(Glamour).to receive(:render).and_raise(Timeout::Error)
      out = described_class.send(:render_messages, messages, 70)
      expect(out).to include("glamour timed out")
      expect(out).to include("hello")
    end
  end
end
