# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::Model do
  let(:test_binding) { Object.new.instance_eval { x = 42; binding } }
  let(:model) { described_class.new(test_binding) }

  describe "#initialize" do
    it "starts in normal mode" do
      expect(model.mode).to eq(:normal)
    end

    it "initializes runtime" do
      expect(model.runtime).to be_a(Claw::Runtime)
    end

    it "starts with empty chat history except system message after init" do
      model.init
      expect(model.chat_history.size).to eq(1)
      expect(model.chat_history.first[:role]).to eq(:system)
    end

    it "has a chat viewport" do
      expect(model.chat_viewport).to be_a(Bubbles::Viewport)
    end
  end

  describe "#last_snapshot_id" do
    it "returns the latest snapshot id" do
      expect(model.last_snapshot_id).to eq(1)  # session_start
    end
  end

  describe "#token_display" do
    it "returns formatted token count" do
      expect(model.token_display).to match(%r{\d+(\.\d+)?k?/\d+(\.\d+)?k})
    end
  end

  describe "#update with AgentTextMsg" do
    it "buffers streaming text" do
      model.update(Claw::TUI::AgentTextMsg.new(text: "hello"))
      # Text is buffered, not yet in chat_history
      expect(model.chat_history.none? { |m| m[:role] == :agent }).to be true
    end
  end

  describe "#update with ToolCallMsg" do
    it "adds tool call to chat history" do
      model.update(Claw::TUI::ToolCallMsg.new(name: "read_var", input: { name: "x" }))
      expect(model.chat_history.last[:role]).to eq(:tool_call)
    end
  end

  describe "#update with ExecutionDoneMsg" do
    it "flushes text buffer and adds agent message" do
      model.update(Claw::TUI::AgentTextMsg.new(text: "result text"))
      model.update(Claw::TUI::ExecutionDoneMsg.new(result: "ok", trace: nil))
      agent_msgs = model.chat_history.select { |m| m[:role] == :agent }
      expect(agent_msgs.size).to eq(1)
      expect(agent_msgs.first[:content]).to eq("result text")
    end
  end

  describe "#update with ExecutionErrorMsg" do
    it "adds error to chat history" do
      model.update(Claw::TUI::ExecutionErrorMsg.new(error: RuntimeError.new("boom")))
      expect(model.chat_history.last[:role]).to eq(:error)
      expect(model.chat_history.last[:content]).to eq("boom")
    end
  end

  describe "#view" do
    it "returns a string" do
      model.init
      output = model.view
      expect(output).to be_a(String)
      expect(output.length).to be > 0
    end
  end
end
