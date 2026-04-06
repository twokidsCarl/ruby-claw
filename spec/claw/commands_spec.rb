# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Commands do
  let(:runtime) { Claw::Runtime.new }
  let(:test_resource_class) do
    Class.new do
      include Claw::Resource
      attr_accessor :value

      def initialize(v = 0) = @value = v
      def snapshot! = @value
      def rollback!(token) = @value = token
      def diff(a, b) = "#{a} → #{b}"
      def to_md = "value=#{@value}"
      def merge_from!(other) = @value = other.value
    end
  end

  before do
    runtime.register("test", test_resource_class.new(42))
    runtime.snapshot!(label: "initial")
  end

  describe ".dispatch" do
    it "returns error for unknown command" do
      result = described_class.dispatch("nope", nil, runtime: runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("Unknown command")
      expect(result[:data][:available]).to include("/snapshot")
    end

    it "returns error when runtime is nil" do
      result = described_class.dispatch("status", nil, runtime: nil)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("Runtime not initialized")
    end
  end

  describe "snapshot" do
    it "creates a snapshot and returns its id" do
      result = described_class.dispatch("snapshot", "test_snap", runtime: runtime)
      expect(result[:type]).to eq(:success)
      expect(result[:data][:id]).to eq(2)
      expect(result[:message]).to include("test_snap")
    end

    it "uses 'manual' label when no arg given" do
      result = described_class.dispatch("snapshot", nil, runtime: runtime)
      expect(result[:type]).to eq(:success)
      expect(runtime.snapshots.last.label).to eq("manual")
    end
  end

  describe "rollback" do
    it "returns error without id" do
      result = described_class.dispatch("rollback", nil, runtime: runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("Usage")
    end

    it "rolls back to the given snapshot" do
      runtime.resources["test"].value = 99
      runtime.snapshot!(label: "changed")
      result = described_class.dispatch("rollback", "1", runtime: runtime)
      expect(result[:type]).to eq(:success)
      expect(runtime.resources["test"].value).to eq(42)
    end
  end

  describe "diff" do
    it "returns error with fewer than 2 snapshots and no arg" do
      solo_runtime = Claw::Runtime.new
      solo_runtime.register("test", test_resource_class.new)
      solo_runtime.snapshot!(label: "only_one")
      result = described_class.dispatch("diff", nil, runtime: solo_runtime)
      expect(result[:type]).to eq(:error)
    end

    it "returns diffs between last two snapshots" do
      runtime.resources["test"].value = 99
      runtime.snapshot!(label: "changed")
      result = described_class.dispatch("diff", nil, runtime: runtime)
      expect(result[:type]).to eq(:data)
      expect(result[:data][:diffs]).to have_key("test")
      expect(result[:data][:diffs]["test"]).to include("→")
    end

    it "accepts explicit snapshot ids" do
      runtime.resources["test"].value = 99
      runtime.snapshot!(label: "changed")
      result = described_class.dispatch("diff", "1 2", runtime: runtime)
      expect(result[:type]).to eq(:data)
      expect(result[:data][:from]).to eq(1)
      expect(result[:data][:to]).to eq(2)
    end
  end

  describe "history" do
    it "returns snapshot list" do
      result = described_class.dispatch("history", nil, runtime: runtime)
      expect(result[:type]).to eq(:data)
      expect(result[:data][:snapshots].size).to eq(1)
      expect(result[:data][:snapshots].first[:label]).to eq("initial")
    end

    it "returns info when no snapshots" do
      empty_rt = Claw::Runtime.new
      empty_rt.register("test", test_resource_class.new)
      result = described_class.dispatch("history", nil, runtime: empty_rt)
      expect(result[:type]).to eq(:info)
    end
  end

  describe "status" do
    it "returns runtime markdown" do
      result = described_class.dispatch("status", nil, runtime: runtime)
      expect(result[:type]).to eq(:data)
      expect(result[:data][:markdown]).to include("Runtime State")
    end
  end

  describe "evolve" do
    it "returns error when claw_dir does not exist" do
      result = described_class.dispatch("evolve", nil, runtime: runtime, claw_dir: "/nonexistent")
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("claw init")
    end
  end

  describe "diff with single id" do
    it "returns usage error when only one id given" do
      runtime.resources["test"].value = 99
      runtime.snapshot!(label: "changed")
      result = described_class.dispatch("diff", "1", runtime: runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("Usage")
    end
  end

  describe "dispatch rescue" do
    it "catches unexpected exceptions from commands" do
      allow(runtime).to receive(:to_md).and_raise(RuntimeError, "boom")
      result = described_class.dispatch("status", nil, runtime: runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("RuntimeError")
      expect(result[:message]).to include("boom")
    end
  end

  describe "role" do
    let(:claw_dir) { Dir.mktmpdir("claw-cmd-role-") }

    after do
      FileUtils.rm_rf(claw_dir)
      Claw::Roles.clear!
    end

    it "lists available roles when no arg" do
      FileUtils.mkdir_p(File.join(claw_dir, "roles"))
      File.write(File.join(claw_dir, "roles", "analyst.md"), "# Analyst")
      result = described_class.dispatch("role", nil, runtime: runtime, claw_dir: claw_dir)
      expect(result[:type]).to eq(:data)
      expect(result[:data][:available]).to include("analyst")
    end

    it "switches role when arg given" do
      FileUtils.mkdir_p(File.join(claw_dir, "roles"))
      File.write(File.join(claw_dir, "roles", "devops.md"), "# DevOps")
      result = described_class.dispatch("role", "devops", runtime: runtime, claw_dir: claw_dir)
      expect(result[:type]).to eq(:success)
      expect(result[:message]).to include("devops")
      expect(Claw::Roles.current[:name]).to eq("devops")
    end
  end

  describe "forge" do
    it "returns error when no arg given" do
      result = described_class.dispatch("forge", nil, runtime: runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("Usage")
    end

    it "returns error when arg is empty" do
      result = described_class.dispatch("forge", "  ", runtime: runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("Usage")
    end

    it "returns error when no binding resource" do
      result = described_class.dispatch("forge", "my_method", runtime: runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("binding")
    end

    it "delegates to Forge.promote when binding available" do
      forge_runtime = Claw::Runtime.new
      forge_runtime.register("test", test_resource_class.new)
      forge_runtime.register("binding", Claw::Resources::BindingResource.new(binding))
      allow(Claw::Forge).to receive(:promote).and_return({ success: true, message: "Promoted!" })

      result = described_class.dispatch("forge", "my_method", runtime: forge_runtime)
      expect(result[:type]).to eq(:success)
      expect(result[:message]).to eq("Promoted!")
    end

    it "returns error when Forge.promote fails" do
      forge_runtime = Claw::Runtime.new
      forge_runtime.register("test", test_resource_class.new)
      forge_runtime.register("binding", Claw::Resources::BindingResource.new(binding))
      allow(Claw::Forge).to receive(:promote).and_return({ success: false, message: "No source" })

      result = described_class.dispatch("forge", "my_method", runtime: forge_runtime)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to eq("No source")
    end
  end
end
