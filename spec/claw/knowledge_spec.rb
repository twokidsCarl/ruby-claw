# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Knowledge do
  describe ".query" do
    it "returns claw overview for 'claw' topic" do
      result = described_class.query("claw")
      expect(result).to start_with("[source: claw]")
      expect(result).to include("ruby-claw")
      expect(result).to include(Claw::VERSION)
    end

    it "returns overview for 'agent' topic (alias)" do
      result = described_class.query("agent")
      expect(result).to include("Agent framework")
    end

    it "returns compaction section for 'compaction' topic" do
      result = described_class.query("compaction")
      expect(result).to include("compaction")
      expect(result).to include("memory_pressure")
    end

    it "returns session section for 'session' topic" do
      result = described_class.query("session")
      expect(result).to include("Session persistence")
    end

    it "returns session section for 'persistence' alias" do
      result = described_class.query("persistence")
      expect(result).to include("Session persistence")
    end

    it "returns tools section for 'tools' topic" do
      result = described_class.query("tools")
      expect(result).to include("Tool system")
      expect(result).to include("search_tools")
    end

    it "returns tools section for 'search_tools' topic" do
      result = described_class.query("search_tools")
      expect(result).to include("Tool system")
    end

    it "returns tools section for 'load_tool' topic" do
      result = described_class.query("load_tool")
      expect(result).to include("load_tool")
    end

    it "returns tools section for 'forge' topic" do
      result = described_class.query("forge")
      expect(result).to include("Tool system")
    end

    it "returns serializer section for 'serializer' topic" do
      result = described_class.query("serializer")
      expect(result).to include("Serializer")
    end

    it "handles case insensitive matching" do
      result = described_class.query("CLAW")
      expect(result).to include("[source: claw]")
    end

    it "handles whitespace in topic" do
      result = described_class.query("  claw  ")
      expect(result).to include("[source: claw]")
    end

    it "falls back to Mana::Knowledge for unknown topics" do
      allow(Mana::Knowledge).to receive(:query).with("quantum_physics").and_return("fallback result")
      result = described_class.query("quantum_physics")
      expect(result).to eq("fallback result")
    end

    it "uses bidirectional matching (topic contains key)" do
      result = described_class.query("claw agent overview")
      expect(result).to include("[source: claw]")
    end
  end
end
