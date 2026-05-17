# frozen_string_literal: true
# encoding: utf-8

require "spec_helper"

RSpec.describe Claw::TUI::StatusBar do
  describe ".visible_width (via send)" do
    # Helper: visible_width is private — use send to test directly.
    def width(str)
      described_class.send(:visible_width, str)
    end

    it "counts plain ASCII as one column per char" do
      expect(width("abc")).to eq(3)
    end

    it "strips ANSI escape sequences" do
      expect(width("\e[31mred\e[0m")).to eq(3)
    end

    it "counts CJK characters as 2 columns each (regression: bare .size returned 1)" do
      # If this regresses to `str.size`, "中文" comes back as 2 and the status
      # bar overflows in a 72-column terminal when the model name has CJK.
      expect(width("中文")).to be >= 4
    end

    it "handles mixed ASCII + CJK + ANSI" do
      expect(width("\e[34m中\e[0m abc")).to be >= 6  # 2 + 1 + 3
    end

    it "handles empty string" do
      expect(width("")).to eq(0)
    end
  end

  describe ".render" do
    let(:runtime) do
      double("runtime",
             snapshots: [double(id: 1)],
             state: :idle,
             current_step: nil)
    end

    let(:model) do
      double("model",
             last_snapshot_id: 1,
             token_display: "0/128k",
             scrolled_up?: false,
             mode: :normal,
             runtime: runtime,
             spinner_view: "")
    end

    it "returns a string at given width" do
      out = described_class.render(model, 72)
      expect(out).to be_a(String)
      expect(out).not_to be_empty
    end

    it "still renders when the model name contains CJK" do
      allow(Mana.config).to receive(:model).and_return("测试-model")
      expect { described_class.render(model, 72) }.not_to raise_error
    end
  end
end
