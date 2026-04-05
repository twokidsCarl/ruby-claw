# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Trace do
  let(:tmpdir) { Dir.mktmpdir("claw_trace_test") }

  after { FileUtils.rm_rf(tmpdir) }

  let(:trace_data) do
    {
      prompt: "compute average of numbers",
      model: "claude-sonnet-4-20250514",
      timestamp: "2026-04-05T10:30:00+08:00",
      total_iterations: 2,
      steps: [
        {
          iteration: 1,
          usage: { input_tokens: 500, output_tokens: 200 },
          latency_ms: 800,
          tool_calls: [
            { name: "read_var", input: { "name" => "numbers" }, result: "[1, 2, 3]" }
          ]
        },
        {
          iteration: 2,
          usage: { input_tokens: 600, output_tokens: 150 },
          latency_ms: 600,
          tool_calls: [
            { name: "write_var", input: { "name" => "avg", "value" => 2.0 }, result: "ok: avg = 2.0" },
            { name: "done", input: { "result" => "2.0" }, result: "ok" }
          ]
        }
      ]
    }
  end

  describe ".write" do
    it "creates a markdown file in traces/ directory" do
      path = described_class.write(trace_data, tmpdir)
      expect(File.exist?(path)).to be true
      expect(path).to include("traces/")
      expect(path).to end_with(".md")
    end

    it "creates the traces directory if missing" do
      traces_dir = File.join(tmpdir, "traces")
      expect(Dir.exist?(traces_dir)).to be false

      described_class.write(trace_data, tmpdir)
      expect(Dir.exist?(traces_dir)).to be true
    end

    it "generates filename from timestamp" do
      path = described_class.write(trace_data, tmpdir)
      expect(File.basename(path)).to eq("20260405_103000.md")
    end
  end

  describe ".render" do
    let(:md) { described_class.render(trace_data) }

    it "includes task prompt" do
      expect(md).to include("# Task: compute average of numbers")
    end

    it "includes metadata" do
      expect(md).to include("Model: claude-sonnet-4-20250514")
      expect(md).to include("Steps: 2")
      expect(md).to include("Total tokens: 1100 in / 350 out")
      expect(md).to include("Total latency: 1400ms")
    end

    it "includes step details" do
      expect(md).to include("## Step 1")
      expect(md).to include("Latency: 800ms")
      expect(md).to include("Tokens: 500 in / 200 out")
      expect(md).to include("## Step 2")
      expect(md).to include("Latency: 600ms")
    end

    it "includes tool call details" do
      expect(md).to include("**read_var**")
      expect(md).to include("**write_var**")
      expect(md).to include("**done**")
    end

    it "truncates long prompts" do
      long_data = trace_data.merge(prompt: "x" * 200)
      md = described_class.render(long_data)
      expect(md).to include("...")
    end
  end

  describe ".render with missing usage" do
    it "handles nil usage gracefully" do
      data = {
        prompt: "test",
        model: "test-model",
        timestamp: "2026-04-05T10:00:00+00:00",
        steps: [{ iteration: 1, usage: nil, latency_ms: 100 }]
      }
      md = described_class.render(data)
      expect(md).to include("Total tokens: 0 in / 0 out")
      expect(md).to include("Latency: 100ms")
    end
  end
end
