# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::AgentExecutor do
  let(:runtime) { instance_double("Claw::TUI::Runtime", transition!: nil) }
  let(:executor) { described_class.new(runtime) }

  describe "#running?" do
    it "returns false initially" do
      expect(executor.running?).to be false
    end
  end

  describe "#cancel!" do
    it "sets running to false and transitions to idle" do
      expect(runtime).to receive(:transition!).with(:idle)
      executor.cancel!
      expect(executor.running?).to be false
    end

    it "kills the thread if one exists" do
      # Start a long-running fake thread
      thread = Thread.new { sleep 100 }
      executor.instance_variable_set(:@thread, thread)
      executor.instance_variable_set(:@running, true)

      expect(runtime).to receive(:transition!).with(:idle)
      executor.cancel!
      sleep 0.05 # Allow thread kill to propagate

      expect(executor.running?).to be false
      expect(thread.alive?).to be false
    end
  end

  describe "#eval_ruby" do
    let(:bind) { binding }

    it "returns success for valid code" do
      result = executor.eval_ruby("1 + 2", bind)
      expect(result[:success]).to be true
      expect(result[:result]).to eq(3)
    end

    it "returns failure for runtime error" do
      result = executor.eval_ruby("raise 'boom'", bind)
      expect(result[:success]).to be false
      expect(result[:error]).to be_a(RuntimeError)
      expect(result[:error].message).to eq("boom")
    end

    it "catches SyntaxError" do
      result = executor.eval_ruby("def end", bind)
      expect(result[:success]).to be false
      expect(result[:error]).to be_a(SyntaxError)
    end

    it "catches NameError" do
      result = executor.eval_ruby("nonexistent_var_xyz_abc", bind)
      expect(result[:success]).to be false
      expect(result[:error]).to be_a(NameError)
    end

    it "handles complex expressions" do
      result = executor.eval_ruby("[1,2,3].map { |x| x * 2 }", bind)
      expect(result[:success]).to be true
      expect(result[:result]).to eq([2, 4, 6])
    end
  end

  describe "#execute" do
    it "returns nil if already running" do
      executor.instance_variable_set(:@running, true)
      result = executor.execute("test", binding) { |_| }
      expect(result).to be_nil
    end
  end
end
