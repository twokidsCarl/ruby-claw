# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::PlanMode do
  include AnthropicHelper

  before do
    Mana.configure { |c| c.api_key = "test-key-000" }
  end

  let(:runtime) do
    r = Claw::Runtime.new
    b = Object.new.instance_eval { binding }
    r.register("binding", Claw::Resources::BindingResource.new(b))
    context = Mana::Context.new
    r.register("context", Claw::Resources::ContextResource.new(context))
    r.snapshot!(label: "start")
    r
  end

  let(:plan_mode) { described_class.new(runtime) }

  describe "#initialize" do
    it "starts inactive" do
      expect(plan_mode.state).to eq(:inactive)
      expect(plan_mode.active?).to be false
      expect(plan_mode.pending?).to be false
      expect(plan_mode.pending_plan).to be_nil
    end
  end

  describe "#toggle!" do
    it "activates to :ready state" do
      result = plan_mode.toggle!
      expect(result).to be true
      expect(plan_mode.state).to eq(:ready)
      expect(plan_mode.active?).to be true
    end

    it "deactivates when toggled again during :ready" do
      plan_mode.toggle!
      result = plan_mode.toggle!
      expect(result).to be false
      expect(plan_mode.state).to eq(:inactive)
    end
  end

  describe "#plan!" do
    it "generates a plan and transitions to :reviewing" do
      stub_anthropic_done("1. Read x\n2. Write x = 42")

      caller_binding = Object.new.instance_eval { binding }
      text = plan_mode.plan!("set x to 42", caller_binding)

      expect(plan_mode.state).to eq(:reviewing)
      expect(plan_mode.pending?).to be true
      expect(plan_mode.pending_plan).not_to be_nil
      expect(plan_mode.pending_plan[:prompt]).to eq("set x to 42")
      expect(text).to be_a(String)
    end
  end

  describe "#execute!" do
    it "raises if no pending plan" do
      expect { plan_mode.execute!(Object.new.instance_eval { binding }) }
        .to raise_error(RuntimeError, /No pending plan/)
    end

    it "executes plan and returns to :inactive" do
      # Phase 1: plan
      stub_anthropic_done("1. Read x\n2. Write x = 42")
      caller_binding = Object.new.instance_eval { binding }
      plan_mode.plan!("set x to 42", caller_binding)

      # Phase 2: execute (stub the fork execution)
      stub_anthropic_done("done")
      success, result = plan_mode.execute!(caller_binding)

      expect(plan_mode.state).to eq(:inactive)
      expect(plan_mode.pending_plan).to be_nil
    end
  end

  describe "#discard!" do
    it "clears plan and returns to inactive" do
      stub_anthropic_done("plan text here")
      caller_binding = Object.new.instance_eval { binding }
      plan_mode.plan!("task", caller_binding)

      plan_mode.discard!
      expect(plan_mode.state).to eq(:inactive)
      expect(plan_mode.pending_plan).to be_nil
    end
  end
end
