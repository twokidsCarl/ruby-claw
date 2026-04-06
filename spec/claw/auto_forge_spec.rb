# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::AutoForge do
  let(:traces_dir) { Dir.mktmpdir("claw-traces-") }
  after { FileUtils.rm_rf(traces_dir) }

  describe ".analyze" do
    it "returns empty for non-existent directory" do
      expect(described_class.analyze("/nonexistent")).to eq([])
    end

    it "returns empty when no traces" do
      expect(described_class.analyze(traces_dir)).to eq([])
    end

    it "detects repeated eval method definitions" do
      # Create trace files with repeated eval calls defining `parse_data`
      4.times do |i|
        File.write(File.join(traces_dir, "trace_#{i}.md"), <<~MD)
          # Trace #{i}
          ## Step 1
          Tool: eval
          ```ruby
          def parse_data(raw)
            raw.split(",")
          end
          ```
        MD
      end

      suggestions = described_class.analyze(traces_dir)
      expect(suggestions.size).to eq(1)
      expect(suggestions.first[:method_name]).to eq("parse_data")
      expect(suggestions.first[:occurrences]).to eq(4)
    end

    it "ignores methods below threshold" do
      2.times do |i|
        File.write(File.join(traces_dir, "trace_#{i}.md"), <<~MD)
          ## Step 1
          Tool: eval
          ```ruby
          def rare_method(x); x; end
          ```
        MD
      end

      suggestions = described_class.analyze(traces_dir)
      expect(suggestions).to be_empty
    end

    it "returns multiple suggestions sorted by frequency" do
      5.times do |i|
        File.write(File.join(traces_dir, "trace_a_#{i}.md"), <<~MD)
          ## Step 1
          Tool: eval
          ```ruby
          def frequent(x); x * 2; end
          def less_frequent(x); x + 1; end
          ```
        MD
      end

      3.times do |i|
        File.write(File.join(traces_dir, "trace_b_#{i}.md"), <<~MD)
          ## Step 1
          Tool: eval
          ```ruby
          def less_frequent(x); x + 1; end
          ```
        MD
      end

      suggestions = described_class.analyze(traces_dir)
      expect(suggestions.size).to eq(2)
      expect(suggestions.first[:method_name]).to eq("less_frequent")
      expect(suggestions.first[:occurrences]).to eq(8)
    end
  end

  describe ".suggest?" do
    it "returns false when no patterns" do
      expect(described_class.suggest?(traces_dir)).to be false
    end

    it "returns true when patterns exceed threshold" do
      3.times do |i|
        File.write(File.join(traces_dir, "t_#{i}.md"), <<~MD)
          Tool: eval
          ```ruby
          def repeated_func(x); x; end
          ```
        MD
      end
      expect(described_class.suggest?(traces_dir)).to be true
    end
  end

  describe ".format_suggestions" do
    it "returns empty string for no suggestions" do
      expect(described_class.format_suggestions([])).to eq("")
    end

    it "formats suggestions with forge commands" do
      suggestions = [{ method_name: "parse", occurrences: 5, sample_code: "" }]
      output = described_class.format_suggestions(suggestions)
      expect(output).to include("/forge parse")
      expect(output).to include("5x")
    end
  end
end
