# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::ToolRegistry do
  let(:tools_dir) { Dir.mktmpdir("claw-registry-") }

  before do
    File.write(File.join(tools_dir, "greet.rb"), <<~RUBY)
      class Greet
        include Claw::Tool
        tool_name   "greet"
        description "Greet a person by name"
        parameter   :name, type: "String", required: true, desc: "Person's name"
        def call(name:)
          "Hello, \#{name}!"
        end
      end
    RUBY
  end

  after { FileUtils.rm_rf(tools_dir) }

  let(:registry) { described_class.new(tools_dir: tools_dir) }

  describe "#search" do
    it "finds tools by keyword" do
      results = registry.search("greet")
      expect(results.size).to eq(1)
      expect(results.first[:name]).to eq("greet")
      expect(results.first[:source]).to eq("project")
    end

    it "marks loaded status" do
      results = registry.search("greet")
      expect(results.first[:loaded]).to be false

      registry.load("greet")
      results = registry.search("greet")
      expect(results.first[:loaded]).to be true
    end
  end

  describe "#load" do
    it "loads a tool and registers with Mana" do
      msg = registry.load("greet")
      expect(msg).to include("loaded successfully")
      expect(registry.loaded?("greet")).to be true

      # Verify it was registered with Mana
      tool_names = Mana.registered_tools.map { |t| t[:name] }
      expect(tool_names).to include("greet")
    end

    it "returns error for unknown tool" do
      msg = registry.load("nonexistent")
      expect(msg).to include("not found")
    end

    it "prevents double loading" do
      registry.load("greet")
      msg = registry.load("greet")
      expect(msg).to include("already loaded")
    end

    it "loaded tool handler is callable via Mana" do
      registry.load("greet")
      handler = Mana.tool_handlers["greet"]
      expect(handler).not_to be_nil
      result = handler.call({ "name" => "World" })
      expect(result).to eq("Hello, World!")
    end
  end

  describe "#unload" do
    it "unloads a loaded tool" do
      registry.load("greet")
      expect(registry.loaded?("greet")).to be true

      msg = registry.unload("greet")
      expect(msg).to include("unloaded")
      expect(registry.loaded?("greet")).to be false
    end

    it "returns error for not-loaded tool" do
      msg = registry.unload("greet")
      expect(msg).to include("not loaded")
    end
  end

  describe "#loaded?" do
    it "returns false initially" do
      expect(registry.loaded?("greet")).to be false
    end
  end

  describe "hub integration" do
    let(:hub) { instance_double(Claw::Hub) }
    let(:hub_registry) { described_class.new(tools_dir: tools_dir, hub: hub) }

    describe "#search with hub" do
      it "queries hub when local results are sparse" do
        allow(hub).to receive(:search).with("rare").and_return([
          { name: "rare_tool", description: "From hub" }
        ])
        results = hub_registry.search("rare")
        expect(results.any? { |r| r[:name] == "rare_tool" }).to be true
        expect(results.find { |r| r[:name] == "rare_tool" }[:source]).to eq("hub")
      end

      it "skips hub results that duplicate local names" do
        allow(hub).to receive(:search).with("greet").and_return([
          { name: "greet", description: "Hub duplicate" }
        ])
        results = hub_registry.search("greet")
        expect(results.count { |r| r[:name] == "greet" }).to eq(1)
      end

      it "handles hub errors gracefully" do
        allow(hub).to receive(:search).and_raise(RuntimeError, "timeout")
        results = hub_registry.search("anything")
        expect(results).to be_an(Array)
      end
    end

    describe "#download_from_hub" do
      it "downloads and refreshes index" do
        allow(hub).to receive(:download)
        result = hub_registry.download_from_hub("some_tool")
        expect(result).to be true
      end

      it "returns false on download error" do
        allow(hub).to receive(:download).and_raise(RuntimeError, "404")
        result = hub_registry.download_from_hub("missing")
        expect(result).to be false
      end

      it "returns false when hub is nil" do
        result = registry.download_from_hub("any")
        expect(result).to be false
      end
    end
  end

  describe "tool handler error handling" do
    it "returns error message when tool call raises" do
      File.write(File.join(tools_dir, "broken.rb"), <<~RUBY)
        class Broken
          include Claw::Tool
          tool_name   "broken"
          description "A tool that always fails"
          def call
            raise "intentional error"
          end
        end
      RUBY
      registry = described_class.new(tools_dir: tools_dir)
      registry.load("broken")
      handler = Mana.tool_handlers["broken"]
      result = handler.call({})
      expect(result).to include("error:")
      expect(result).to include("intentional error")
    end
  end
end
