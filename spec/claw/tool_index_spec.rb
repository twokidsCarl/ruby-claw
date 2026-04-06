# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::ToolIndex do
  let(:tools_dir) { Dir.mktmpdir("claw-tools-") }

  before do
    # Create sample tool files
    File.write(File.join(tools_dir, "format_report.rb"), <<~RUBY)
      class FormatReport
        include Claw::Tool
        tool_name   "format_report"
        description "Format raw data into a readable report"
        parameter   :data, type: "Hash", required: true, desc: "Raw data"
        def call(data:)
          data.to_s
        end
      end
    RUBY

    File.write(File.join(tools_dir, "analyze_data.rb"), <<~RUBY)
      class AnalyzeData
        include Claw::Tool
        tool_name   "analyze_data"
        description "Analyze dataset and return statistics"
        parameter   :dataset, type: "Array", required: true, desc: "Data to analyze"
        def call(dataset:)
          { count: dataset.size }
        end
      end
    RUBY

    # A non-tool Ruby file (no tool_name) — should be skipped
    File.write(File.join(tools_dir, "helper.rb"), <<~RUBY)
      module Helper
        def self.cleanup; end
      end
    RUBY
  end

  after { FileUtils.rm_rf(tools_dir) }

  describe "#initialize" do
    it "scans and indexes tool files" do
      index = described_class.new(tools_dir)
      expect(index.entries.size).to eq(2)
    end

    it "extracts name and description" do
      index = described_class.new(tools_dir)
      entry = index.entries.find { |e| e.name == "format_report" }
      expect(entry).not_to be_nil
      expect(entry.description).to eq("Format raw data into a readable report")
      expect(entry.path).to end_with("format_report.rb")
    end

    it "handles non-existent directory" do
      index = described_class.new("/nonexistent/path")
      expect(index.entries).to be_empty
    end

    it "handles nil directory" do
      index = described_class.new(nil)
      expect(index.entries).to be_empty
    end
  end

  describe "#search" do
    let(:index) { described_class.new(tools_dir) }

    it "finds tools by name keyword" do
      results = index.search("format")
      expect(results.size).to eq(1)
      expect(results.first.name).to eq("format_report")
    end

    it "finds tools by description keyword" do
      results = index.search("statistics")
      expect(results.size).to eq(1)
      expect(results.first.name).to eq("analyze_data")
    end

    it "returns all tools for empty keyword" do
      results = index.search("")
      expect(results.size).to eq(2)
    end

    it "returns empty for no match" do
      results = index.search("nonexistent_xyz")
      expect(results).to be_empty
    end

    it "is case-insensitive" do
      results = index.search("FORMAT")
      expect(results.size).to eq(1)
    end
  end

  describe "#find" do
    let(:index) { described_class.new(tools_dir) }

    it "finds by exact name" do
      expect(index.find("analyze_data")).not_to be_nil
    end

    it "returns nil for missing name" do
      expect(index.find("missing")).to be_nil
    end
  end

  describe "#load_tool" do
    let(:index) { described_class.new(tools_dir) }

    it "loads a tool class from file" do
      klass = index.load_tool("format_report")
      expect(klass).not_to be_nil
      expect(klass.tool_name).to eq("format_report")
    end

    it "returns nil for unknown tool" do
      expect(index.load_tool("nonexistent")).to be_nil
    end

    it "loaded class is callable" do
      klass = index.load_tool("format_report")
      result = klass.new.call(data: { x: 1 })
      expect(result).to be_a(String)
    end
  end

  describe "#scan!" do
    it "refreshes the index when new files are added" do
      index = described_class.new(tools_dir)
      expect(index.entries.size).to eq(2)

      File.write(File.join(tools_dir, "new_tool.rb"), <<~RUBY)
        class NewTool
          include Claw::Tool
          tool_name   "new_tool"
          description "A brand new tool"
          def call; end
        end
      RUBY

      index.scan!
      expect(index.entries.size).to eq(3)
    end
  end
end
