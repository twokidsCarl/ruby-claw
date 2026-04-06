# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw do
  describe ".config" do
    it "returns a Config instance" do
      expect(described_class.config).to be_a(Claw::Config)
    end
  end

  describe ".configure" do
    it "yields config and returns it" do
      result = described_class.configure { |c| c.console_port = 9999 }
      expect(result.console_port).to eq(9999)
    ensure
      described_class.config.console_port = 4567
    end
  end

  describe ".memory" do
    it "returns current memory (may be nil)" do
      expect(described_class.memory).to be_nil.or be_a(Claw::Memory)
    end
  end

  describe ".tool_registry" do
    it "is nil by default" do
      saved = described_class.tool_registry
      described_class.instance_variable_set(:@tool_registry, nil)
      expect(described_class.tool_registry).to be_nil
      described_class.instance_variable_set(:@tool_registry, saved)
    end
  end

  describe ".init_tool_registry" do
    it "creates a registry with default tools_dir" do
      registry = described_class.init_tool_registry
      expect(registry).to be_a(Claw::ToolRegistry)
    ensure
      described_class.instance_variable_set(:@tool_registry, nil)
    end
  end

  describe ".reset!" do
    it "resets config, registry, and thread-locals" do
      described_class.configure { |c| c.console_port = 1234 }
      described_class.reset!
      expect(described_class.config.console_port).to eq(4567)
      expect(described_class.tool_registry).to be_nil
    end
  end

  describe ".incognito" do
    it "disables memory within the block" do
      described_class.incognito do
        expect(Claw::Memory.incognito?).to be true
      end
      expect(Claw::Memory.incognito?).to be false
    end
  end

  describe "registered Mana tools" do
    it "registers remember tool" do
      tool = Mana.registered_tools.find { |t| t[:name] == "remember" }
      expect(tool).not_to be_nil
      expect(tool[:description]).to include("memory")
    end

    it "registers search_tools" do
      tool = Mana.registered_tools.find { |t| t[:name] == "search_tools" }
      expect(tool).not_to be_nil
    end

    it "registers load_tool" do
      tool = Mana.registered_tools.find { |t| t[:name] == "load_tool" }
      expect(tool).not_to be_nil
    end

    it "remember handler returns memory not available when no memory" do
      handler = Mana.tool_handlers["remember"]
      result = handler.call({ "content" => "test" })
      expect(result).to include("not available").or include("Remembered")
    end

    it "search_tools handler returns message when no registry" do
      saved = Claw.tool_registry
      Claw.instance_variable_set(:@tool_registry, nil)
      handler = Mana.tool_handlers["search_tools"]
      result = handler.call({ "query" => "test" })
      expect(result).to include("not initialized")
    ensure
      Claw.instance_variable_set(:@tool_registry, saved)
    end

    it "load_tool handler returns message when no registry" do
      saved = Claw.tool_registry
      Claw.instance_variable_set(:@tool_registry, nil)
      handler = Mana.tool_handlers["load_tool"]
      result = handler.call({ "tool_name" => "test" })
      expect(result).to include("not initialized")
    ensure
      Claw.instance_variable_set(:@tool_registry, saved)
    end
  end
end
