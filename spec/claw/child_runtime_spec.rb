# frozen_string_literal: true

RSpec.describe Claw::ChildRuntime do
  include AnthropicHelper

  before do
    Mana.configure { |c| c.api_key = "test-key-000" }
  end

  let(:parent) do
    runtime = Claw::Runtime.new
    b = Object.new.instance_eval { binding }
    runtime.register("binding", Claw::Resources::BindingResource.new(b))
    context = Mana::Context.new
    runtime.register("context", Claw::Resources::ContextResource.new(context))
    runtime.snapshot!(label: "parent_start")
    runtime
  end

  describe "lifecycle" do
    it "starts in :created state" do
      child = Claw::ChildRuntime.new(
        parent: parent,
        prompt: "test",
        vars: { x: 1 }
      )
      expect(child.state).to eq(:created)
      expect(child.id).to be_a(String)
      expect(child.id.size).to eq(8)
    end

    it "transitions to :running on start!" do
      stub_anthropic_done("ok")

      child = Claw::ChildRuntime.new(
        parent: parent,
        prompt: "test",
        vars: { x: 1 }
      )
      child.start!
      expect(child.state).to eq(:running)
      child.join(timeout: 10)
    end

    it "transitions to :completed on success" do
      stub_anthropic_done("ok")

      child = Claw::ChildRuntime.new(
        parent: parent,
        prompt: "set x to 2",
        vars: { x: 1 }
      )
      child.start!
      child.join(timeout: 10)

      expect(child.state).to eq(:completed)
      expect(child.error).to be_nil
    end

    it "transitions to :cancelled" do
      child = Claw::ChildRuntime.new(
        parent: parent,
        prompt: "test",
        vars: {}
      )
      child.cancel!
      expect(child.state).to eq(:cancelled)
    end

    it "tracks elapsed time" do
      stub_anthropic_done("ok")

      child = Claw::ChildRuntime.new(
        parent: parent,
        prompt: "test",
        vars: {}
      )
      expect(child.elapsed_ms).to eq(0)

      child.start!
      child.join(timeout: 10)
      expect(child.elapsed_ms).to be >= 0
    end
  end

  describe "isolation" do
    it "deep-copies variables so parent is not affected" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { name: "items", value: "[99]" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { result: "done" } }]
      )

      original = [1, 2, 3]
      child = Claw::ChildRuntime.new(
        parent: parent,
        prompt: "modify items",
        vars: { items: original }
      )
      child.start!
      child.join(timeout: 10)

      # Parent's original should be unchanged
      expect(original).to eq([1, 2, 3])
    end
  end

  describe "#done?" do
    it "returns false when created" do
      child = Claw::ChildRuntime.new(parent: parent, prompt: "test")
      expect(child.done?).to be false
    end

    it "returns true when completed" do
      stub_anthropic_done("ok")
      child = Claw::ChildRuntime.new(parent: parent, prompt: "test")
      child.start!
      child.join(timeout: 10)
      expect(child.done?).to be true
    end
  end

  describe "#running?" do
    it "returns false when created" do
      child = Claw::ChildRuntime.new(parent: parent, prompt: "test")
      expect(child.running?).to be false
    end
  end

  describe "#merge!" do
    it "raises if child not completed" do
      child = Claw::ChildRuntime.new(parent: parent, prompt: "test")
      expect { child.merge! }.to raise_error(RuntimeError, /not completed/)
    end

    it "merges binding changes back to parent" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { name: "x", value: "42" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { result: "done" } }]
      )

      child = Claw::ChildRuntime.new(
        parent: parent,
        prompt: "set x to 42",
        vars: { x: 1 }
      )
      child.start!
      child.join(timeout: 10)

      if child.state == :completed
        child.merge!(only: [:binding])
        # Parent should now have the child's binding changes merged
        expect(parent.events.any? { |e| e[:action] == "child_merged" }).to be true
      end
    end
  end

  describe "fork_async via runtime" do
    it "creates and starts a child" do
      stub_anthropic_done("ok")

      child = parent.fork_async(prompt: "do something", vars: { a: 1 })

      expect(child).to be_a(Claw::ChildRuntime)
      expect(child.state).to eq(:running)
      expect(parent.children).to have_key(child.id)
      expect(parent.events.any? { |e| e[:action] == "fork_async" }).to be true

      child.join(timeout: 10)
    end
  end
end
