# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Runtime do
  # Simple in-memory resource for testing
  let(:test_resource_class) do
    Class.new do
      include Claw::Resource

      attr_accessor :value

      def initialize(initial = 0)
        @value = initial
      end

      def snapshot!
        @value
      end

      def rollback!(token)
        @value = token
      end

      def diff(token_a, token_b)
        "#{token_a} → #{token_b}"
      end

      def to_md
        "value=#{@value}"
      end
    end
  end

  let(:runtime) { described_class.new }
  let(:resource_a) { test_resource_class.new(10) }
  let(:resource_b) { test_resource_class.new(20) }

  describe "#register" do
    it "registers a resource by name" do
      runtime.register("a", resource_a)
      expect(runtime.resources).to include("a" => resource_a)
    end

    it "raises if resource does not include Claw::Resource" do
      expect { runtime.register("bad", Object.new) }.to raise_error(ArgumentError, /must include/)
    end

    it "raises on duplicate name" do
      runtime.register("a", resource_a)
      expect { runtime.register("a", resource_b) }.to raise_error(ArgumentError, /already registered/)
    end

    it "raises if called after first snapshot" do
      runtime.register("a", resource_a)
      runtime.snapshot!
      expect { runtime.register("b", resource_b) }.to raise_error(RuntimeError, /Cannot register/)
    end
  end

  describe "#snapshot!" do
    before do
      runtime.register("a", resource_a)
      runtime.register("b", resource_b)
    end

    it "returns an incrementing snapshot id" do
      id1 = runtime.snapshot!
      id2 = runtime.snapshot!
      expect(id1).to eq(1)
      expect(id2).to eq(2)
    end

    it "records snapshot metadata" do
      runtime.snapshot!(label: "initial")
      expect(runtime.snapshots.size).to eq(1)
      expect(runtime.snapshots.first.label).to eq("initial")
      expect(runtime.snapshots.first.id).to eq(1)
    end

    it "logs a snapshot event" do
      runtime.snapshot!(label: "test")
      expect(runtime.events.last[:action]).to eq("snapshot")
    end
  end

  describe "#rollback!" do
    before do
      runtime.register("a", resource_a)
      runtime.register("b", resource_b)
    end

    it "restores resources to a previous snapshot state" do
      runtime.snapshot!(label: "before")
      resource_a.value = 99
      resource_b.value = 88

      runtime.rollback!(1)

      expect(resource_a.value).to eq(10)
      expect(resource_b.value).to eq(20)
    end

    it "raises on unknown snapshot id" do
      expect { runtime.rollback!(999) }.to raise_error(ArgumentError, /Unknown snapshot/)
    end

    it "logs a rollback event" do
      runtime.snapshot!
      runtime.rollback!(1)
      expect(runtime.events.last[:action]).to eq("rollback")
    end
  end

  describe "#diff" do
    before do
      runtime.register("a", resource_a)
    end

    it "returns per-resource diff" do
      runtime.snapshot!
      resource_a.value = 42
      runtime.snapshot!

      result = runtime.diff(1, 2)
      expect(result["a"]).to eq("10 → 42")
    end

    it "raises on unknown snapshot ids" do
      expect { runtime.diff(1, 2) }.to raise_error(ArgumentError)
    end
  end

  describe "#fork" do
    before do
      runtime.register("a", resource_a)
    end

    it "returns [true, result] on success" do
      success, result = runtime.fork(label: "test") do
        resource_a.value = 42
        "done"
      end

      expect(success).to be true
      expect(result).to eq("done")
      expect(resource_a.value).to eq(42)
    end

    it "rolls back and returns [false, error] on failure" do
      success, error = runtime.fork(label: "risky") do
        resource_a.value = 99
        raise "boom"
      end

      expect(success).to be false
      expect(error).to be_a(RuntimeError)
      expect(error.message).to eq("boom")
      expect(resource_a.value).to eq(10)
    end

    it "logs fork_rollback event on failure" do
      runtime.fork { raise "oops" }
      expect(runtime.events.any? { |e| e[:action] == "fork_rollback" }).to be true
    end
  end

  describe "#to_md" do
    it "renders Markdown with resources and snapshots" do
      runtime.register("a", resource_a)
      runtime.snapshot!(label: "init")

      md = runtime.to_md
      expect(md).to include("# Runtime State")
      expect(md).to include("### a")
      expect(md).to include("value=10")
      expect(md).to include("#1")
      expect(md).to include("init")
    end
  end
end
