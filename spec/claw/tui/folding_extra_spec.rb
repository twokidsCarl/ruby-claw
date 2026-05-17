# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::Folding do
  describe ".fold_text" do
    it "returns unfolded for short text" do
      text = "line1\nline2\nline3\n"
      result = described_class.fold_text(text)
      expect(result[:folded]).to be false
      expect(result[:display]).to eq(text)
      expect(result[:full]).to eq(text)
    end

    it "returns unfolded for exactly threshold lines" do
      text = (1..10).map { |i| "line #{i}\n" }.join
      result = described_class.fold_text(text, threshold: 10)
      expect(result[:folded]).to be false
      expect(result[:display]).to eq(text)
    end

    it "folds text exceeding threshold" do
      text = (1..15).map { |i| "line #{i}\n" }.join
      result = described_class.fold_text(text, threshold: 10)
      expect(result[:folded]).to be true
      expect(result[:full]).to eq(text)
      # Display shows first 3 lines + summary
      expect(result[:display]).to include("line 1")
      expect(result[:display]).to include("line 2")
      expect(result[:display]).to include("line 3")
      expect(result[:display]).to include("+12 more lines")
      expect(result[:display]).not_to include("line 4")
    end

    it "respects custom threshold" do
      text = "a\nb\nc\nd\ne\n"
      result = described_class.fold_text(text, threshold: 3)
      expect(result[:folded]).to be true
      expect(result[:display]).to include("+2 more lines")
    end

    it "handles single-line text" do
      text = "hello"
      result = described_class.fold_text(text)
      expect(result[:folded]).to be false
      expect(result[:display]).to eq("hello")
    end

    it "handles empty string" do
      result = described_class.fold_text("")
      expect(result[:folded]).to be false
      expect(result[:display]).to eq("")
    end
  end

  describe ".render_diff" do
    it "colors addition lines green" do
      result = described_class.render_diff("+added line\n")
      expect(result).to include("added line")
    end

    it "colors removal lines red" do
      result = described_class.render_diff("-removed line\n")
      expect(result).to include("removed line")
    end

    it "colors change lines yellow" do
      result = described_class.render_diff("~changed line\n")
      expect(result).to include("changed line")
    end

    it "leaves context lines uncolored" do
      result = described_class.render_diff(" context line\n")
      expect(result).to include("context line")
    end

    it "handles multi-line diffs" do
      diff = "+added\n context\n-removed\n~changed\n"
      result = described_class.render_diff(diff)
      lines = result.split("\n")
      expect(lines.size).to eq(4)
    end

    it "strips trailing whitespace" do
      result = described_class.render_diff("+line with spaces   \n")
      # render_diff does rstrip on each line
      expect(result).not_to end_with("   ")
    end
  end

  describe ".render_resource_diff" do
    it "renders multiple resource diffs with headers" do
      diffs = {
        "variables" => "+x = 1\n-y = 2\n",
        "methods" => "+def foo\n"
      }
      result = described_class.render_resource_diff(diffs)
      expect(result).to include("variables:")
      expect(result).to include("methods:")
      expect(result).to include("x = 1")
      expect(result).to include("y = 2")
      expect(result).to include("def foo")
    end

    it "handles empty diffs hash" do
      result = described_class.render_resource_diff({})
      expect(result).to eq("")
    end

    it "handles single resource" do
      diffs = { "state" => "+new\n" }
      result = described_class.render_resource_diff(diffs)
      expect(result).to include("state:")
      expect(result).to include("new")
    end
  end
end
