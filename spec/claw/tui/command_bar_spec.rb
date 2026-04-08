# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::CommandBar do
  describe "HINTS" do
    it "contains expected slash commands" do
      expect(described_class::HINTS).to include("/snapshot", "/rollback", "/diff", "/history")
      expect(described_class::HINTS).to be_frozen
    end
  end

  describe ".render" do
    let(:model) { double("model") }

    it "renders with sufficient width" do
      result = described_class.render(model, 80)
      expect(result).to include("/snapshot")
      expect(result).to include("/rollback")
      expect(result).to include("ctrl+c")
      expect(result).to include("quit")
    end

    it "renders with narrow width" do
      result = described_class.render(model, 40)
      expect(result).to include("/snapshot")
      expect(result).to include("ctrl+c")
    end

    it "includes all HINTS" do
      result = described_class.render(model, 120)
      described_class::HINTS.each do |hint|
        expect(result).to include(hint)
      end
    end
  end
end
