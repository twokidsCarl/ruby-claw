# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::Model do
  let(:test_binding) { Object.new.instance_eval { x = 42; binding } }
  let(:model) { described_class.new(test_binding) }

  # Helper: validate Bubbletea MVU protocol — init/update must return [model, command]
  def expect_mvu_tuple(result)
    expect(result).to be_an(Array), "expected [model, command] tuple, got #{result.class}"
    expect(result.size).to eq(2), "expected 2-element tuple, got #{result.size} elements"
    expect(result[0]).to respond_to(:update), "first element must be a model (respond to #update)"
    expect(result[0]).to respond_to(:view), "first element must be a model (respond to #view)"
  end

  describe "#initialize" do
    it "starts in normal mode" do
      expect(model.mode).to eq(:normal)
    end

    it "initializes runtime" do
      expect(model.runtime).to be_a(Claw::Runtime)
    end

    it "starts with empty chat history except system message after init" do
      result = model.init
      expect_mvu_tuple(result)
      expect(model.chat_history.size).to eq(1)
      expect(model.chat_history.first[:role]).to eq(:system)
    end

    it "has a chat viewport" do
      expect(model.chat_viewport).to be_a(Bubbles::Viewport)
    end
  end

  describe "#init" do
    it "returns [model, command] tuple" do
      result = model.init
      expect_mvu_tuple(result)
    end

    it "returns a batch command with spinner tick" do
      _model, cmd = model.init
      expect(cmd).to be_a(Bubbletea::BatchCommand)
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

  describe "#update" do
    context "with AgentTextMsg" do
      it "returns [model, command] tuple" do
        result = model.update(Claw::TUI::AgentTextMsg.new(text: "hello"))
        expect_mvu_tuple(result)
      end

      it "buffers streaming text" do
        model.update(Claw::TUI::AgentTextMsg.new(text: "hello"))
        # Text is buffered, not yet in chat_history
        expect(model.chat_history.none? { |m| m[:role] == :agent }).to be true
      end
    end

    context "with ToolCallMsg" do
      it "returns [model, command] tuple" do
        result = model.update(Claw::TUI::ToolCallMsg.new(name: "read_var", input: { name: "x" }))
        expect_mvu_tuple(result)
      end

      it "adds tool call to chat history" do
        model.update(Claw::TUI::ToolCallMsg.new(name: "read_var", input: { name: "x" }))
        expect(model.chat_history.last[:role]).to eq(:tool_call)
      end
    end

    context "with ToolResultMsg" do
      it "returns [model, command] tuple" do
        result = model.update(Claw::TUI::ToolResultMsg.new(name: "read_var", result: "42"))
        expect_mvu_tuple(result)
      end

      it "adds result to chat history when not ok:" do
        model.update(Claw::TUI::ToolResultMsg.new(name: "read_var", result: "42"))
        expect(model.chat_history.last[:role]).to eq(:tool_result)
      end

      it "skips result starting with ok:" do
        before_count = model.chat_history.size
        model.update(Claw::TUI::ToolResultMsg.new(name: "read_var", result: "ok: done"))
        expect(model.chat_history.size).to eq(before_count)
      end
    end

    context "with ExecutionDoneMsg" do
      it "returns [model, command] tuple" do
        result = model.update(Claw::TUI::ExecutionDoneMsg.new(result: "ok", trace: nil))
        expect_mvu_tuple(result)
      end

      it "flushes text buffer and adds agent message" do
        model.update(Claw::TUI::AgentTextMsg.new(text: "result text"))
        model.update(Claw::TUI::ExecutionDoneMsg.new(result: "ok", trace: nil))
        agent_msgs = model.chat_history.select { |m| m[:role] == :agent }
        expect(agent_msgs.size).to eq(1)
        expect(agent_msgs.first[:content]).to eq("result text")
      end
    end

    context "with ExecutionErrorMsg" do
      it "returns [model, command] tuple" do
        result = model.update(Claw::TUI::ExecutionErrorMsg.new(error: RuntimeError.new("boom")))
        expect_mvu_tuple(result)
      end

      it "adds error to chat history" do
        model.update(Claw::TUI::ExecutionErrorMsg.new(error: RuntimeError.new("boom")))
        expect(model.chat_history.last[:role]).to eq(:error)
        expect(model.chat_history.last[:content]).to eq("boom")
      end
    end

    context "with CommandResultMsg" do
      it "returns [model, command] tuple" do
        result = model.update(Claw::TUI::CommandResultMsg.new(
          result: { type: :success, message: "done" }, cmd: "status"
        ))
        expect_mvu_tuple(result)
      end
    end

    context "with StateChangeMsg" do
      it "returns [model, command] tuple" do
        result = model.update(Claw::TUI::StateChangeMsg.new(
          old_state: :idle, new_state: :thinking, step: nil
        ))
        expect_mvu_tuple(result)
      end
    end

    context "with unknown message type" do
      it "returns [model, command] tuple" do
        result = model.update(Bubbletea::Message.new)
        expect_mvu_tuple(result)
      end
    end

    context "with KeyMessage" do
      def make_key(char)
        runes = char.bytes.size == 1 ? [char.ord] : []
        Bubbletea::KeyMessage.new(key_type: 0, runes: runes, name: char)
      end

      it "returns [model, command] tuple for regular key" do
        result = model.update(make_key("a"))
        expect_mvu_tuple(result)
      end

      it "appends character to input_text" do
        model.update(make_key("a"))
        expect(model.input_text).to eq("a")
      end

      it "returns [model, command] tuple for backspace" do
        model.instance_variable_set(:@input_text, "abc")
        result = model.update(make_key("backspace"))
        expect_mvu_tuple(result)
        expect(model.input_text).to eq("ab")
      end

      it "returns [model, QuitCommand] for ctrl+c" do
        result = model.update(make_key("ctrl+c"))
        expect_mvu_tuple(result)
        _m, cmd = result
        expect(cmd).to be_a(Bubbletea::QuitCommand)
      end

      it "returns [model, QuitCommand] for ctrl+d" do
        result = model.update(make_key("ctrl+d"))
        expect_mvu_tuple(result)
        _m, cmd = result
        expect(cmd).to be_a(Bubbletea::QuitCommand)
      end
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
