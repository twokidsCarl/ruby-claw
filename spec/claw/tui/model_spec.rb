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

  def make_key(char)
    runes = char.bytes.size == 1 ? [char.ord] : []
    Bubbletea::KeyMessage.new(key_type: 0, runes: runes, name: char)
  end

  def submit(model, text)
    model.textarea.value = text
    model.update(make_key("enter"))
  end

  describe "#initialize" do
    it "starts in normal mode" do
      expect(model.mode).to eq(:normal)
    end

    it "initializes runtime" do
      expect(model.runtime).to be_a(Claw::Runtime)
    end

    it "has a textarea" do
      expect(model.textarea).to be_a(Bubbles::TextArea)
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
      it "returns [model, command] tuple for regular key" do
        result = model.update(make_key("a"))
        expect_mvu_tuple(result)
      end

      it "appends character to textarea" do
        model.update(make_key("a"))
        expect(model.textarea.value).to eq("a")
      end

      it "resets textarea on ctrl+c when idle" do
        model.textarea.value = "some text"
        result = model.update(make_key("ctrl+c"))
        expect_mvu_tuple(result)
        expect(model.textarea.value).to eq("")
      end

      it "returns [model, QuitCommand] for ctrl+d" do
        result = model.update(make_key("ctrl+d"))
        expect_mvu_tuple(result)
        _m, cmd = result
        expect(cmd).to be_a(Bubbletea::QuitCommand)
      end
    end
  end

  describe "input submission" do
    before { model.init }

    it "does not quit on 'q'" do
      result = submit(model, "q")
      expect_mvu_tuple(result)
      _m, cmd = result
      expect(cmd).not_to be_a(Bubbletea::QuitCommand)
    end

    it "quits on 'exit'" do
      result = submit(model, "exit")
      _m, cmd = result
      expect(cmd).to be_a(Bubbletea::QuitCommand)
    end

    it "quits on 'quit'" do
      result = submit(model, "quit")
      _m, cmd = result
      expect(cmd).to be_a(Bubbletea::QuitCommand)
    end

    it "evaluates ruby expression directly" do
      submit(model, "42 + 1")
      ruby_msgs = model.chat_history.select { |m| m[:role] == :ruby }
      expect(ruby_msgs.size).to eq(1)
      expect(ruby_msgs.first[:content]).to include("43")
    end

    it "enters multiline mode for incomplete ruby" do
      model.textarea.value = "def foo"
      model.update(make_key("enter"))
      # Textarea should still have content (newline added, not submitted)
      expect(model.textarea.value).to include("def foo")
      expect(model.textarea.line_count).to be >= 2
    end

    it "submits complete multiline ruby" do
      model.textarea.value = "def foo\n  \"hi\"\nend"
      model.update(make_key("enter"))
      ruby_msgs = model.chat_history.select { |m| m[:role] == :ruby }
      expect(ruby_msgs.size).to eq(1)
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

  describe "SyntaxError handling (#8/#12)" do
    before { model.init }

    it "does not crash on bare 'end'" do
      result = submit(model, "end")
      expect_mvu_tuple(result)
      # 'end' is invalid Ruby syntax → goes to AI via smart routing (no crash)
      expect(model.chat_history.size).to be > 1
    end

    it "does not crash on 'deff 2 1'" do
      result = submit(model, "deff 2 1")
      expect_mvu_tuple(result)
      # Invalid syntax → sent to AI, not crash
      expect(model.chat_history.size).to be > 1
    end
  end

  describe "smart input routing (#3)" do
    before { model.init }

    it "evaluates valid Ruby directly" do
      submit(model, "1 + 1")
      ruby_msgs = model.chat_history.select { |m| m[:role] == :ruby }
      expect(ruby_msgs.size).to eq(1)
      expect(ruby_msgs.first[:content]).to include("2")
    end

    it "sends non-Ruby syntax to AI (e.g. Chinese text)" do
      submit(model, "你好世界")
      ruby_msgs = model.chat_history.select { |m| m[:role] == :ruby }
      expect(ruby_msgs).to be_empty
    end

    it "shows error for single-word NameError (no AI fallback)" do
      submit(model, "undefined_xyz_var")
      errors = model.chat_history.select { |m| m[:role] == :error }
      expect(errors.size).to eq(1)
      expect(errors.first[:content]).to include("NameError")
    end

    it "evaluates string literals as Ruby" do
      submit(model, '"hello world"')
      ruby_msgs = model.chat_history.select { |m| m[:role] == :ruby }
      expect(ruby_msgs.size).to eq(1)
      expect(ruby_msgs.first[:content]).to include("hello world")
    end

    it "evaluates array literals as Ruby" do
      submit(model, "[1, 2, 3]")
      ruby_msgs = model.chat_history.select { |m| m[:role] == :ruby }
      expect(ruby_msgs.size).to eq(1)
      expect(ruby_msgs.first[:content]).to include("1")
    end

    it "returns MVU tuple from handle_smart_input" do
      result = submit(model, "42")
      expect_mvu_tuple(result)
    end
  end

  describe "input history (#6)" do
    before { model.init }

    it "records submitted input" do
      submit(model, "1 + 1")
      expect(model.input_history).to eq(["1 + 1"])
    end

    it "navigates up to previous input" do
      submit(model, "1 + 1")
      submit(model, "2 + 2")
      model.update(make_key("up"))
      expect(model.textarea.value).to eq("2 + 2")
    end

    it "navigates up twice to first input" do
      submit(model, "first")
      submit(model, "second")
      model.update(make_key("up"))
      model.update(make_key("up"))
      expect(model.textarea.value).to eq("first")
    end

    it "navigates down back to empty" do
      submit(model, "1 + 1")
      model.update(make_key("up"))
      model.update(make_key("down"))
      expect(model.textarea.value).to eq("")
    end

    it "does nothing when history is empty" do
      model.update(make_key("up"))
      expect(model.textarea.value).to eq("")
    end

    it "does not go past oldest entry" do
      submit(model, "only_one")
      model.update(make_key("up"))
      model.update(make_key("up"))  # should stay at oldest
      expect(model.textarea.value).to eq("only_one")
    end

    it "preserves saved input after up/down cycle" do
      model.textarea.value = "partial"
      model.update(make_key("a"))  # type 'a' to get "partiala" in textarea
      submit(model, "1 + 1")
      # Type something, then navigate up and back down
      model.textarea.value = "typing..."
      model.update(make_key("up"))
      expect(model.textarea.value).to eq("1 + 1")
      model.update(make_key("down"))
      expect(model.textarea.value).to eq("typing...")
    end
  end

  describe "tab completion (#7)" do
    before { model.init }

    it "completes single candidate" do
      submit(model, "def zzz_unique_test_method; end")
      model.textarea.value = "zzz_unique"
      model.update(make_key("tab"))
      expect(model.textarea.value).to eq("zzz_unique_test_method")
    end

    it "shows multiple candidates in chat" do
      model.textarea.value = "/h"
      model.update(make_key("tab"))
      system_msgs = model.chat_history.select { |m| m[:role] == :system }
      expect(system_msgs.size).to be >= 2  # init msg + candidates
    end

    it "does nothing on empty prefix" do
      model.textarea.value = ""
      before_count = model.chat_history.size
      model.update(make_key("tab"))
      expect(model.chat_history.size).to eq(before_count)
    end

    it "does nothing when no matches" do
      model.textarea.value = "zzz_no_match_xyz_999"
      before_count = model.chat_history.size
      model.update(make_key("tab"))
      expect(model.chat_history.size).to eq(before_count)
    end

    it "completes slash commands" do
      model.textarea.value = "/sn"
      model.update(make_key("tab"))
      expect(model.textarea.value).to eq("/snapshot")
    end
  end

  describe "removed commands (#13/#16)" do
    before { model.init }

    it "/ls dispatches to commands module (not object explorer)" do
      submit(model, "/ls")
      # /ls is no longer in handle_slash, so it goes to Claw::Commands.dispatch
      # which returns unknown command error
      errors = model.chat_history.select { |m| m[:role] == :error }
      expect(errors.size).to be >= 1
    end

    it "/whereami dispatches to commands module" do
      submit(model, "/whereami")
      errors = model.chat_history.select { |m| m[:role] == :error }
      expect(errors.size).to be >= 1
    end
  end

  describe "/source REPL fallback (#14)" do
    before { model.init }

    it "shows tracked REPL definition for /source" do
      submit(model, "def zzz_src_test; 42; end")
      submit(model, "/source zzz_src_test")
      system_msgs = model.chat_history.select { |m| m[:role] == :system && m[:content]&.include?("zzz_src_test") }
      expect(system_msgs).not_to be_empty
    end
  end

  describe "eval_ruby error handling" do
    it "catches SyntaxError in eval_ruby" do
      result = model.executor.eval_ruby("def end", model.send(:instance_variable_get, :@caller_binding))
      expect(result[:success]).to be false
      expect(result[:error]).to be_a(SyntaxError)
    end

    it "catches NameError in eval_ruby" do
      result = model.executor.eval_ruby("undefined_var_xyz", model.send(:instance_variable_get, :@caller_binding))
      expect(result[:success]).to be false
      expect(result[:error]).to be_a(NameError)
    end

    it "returns success for valid Ruby" do
      result = model.executor.eval_ruby("1 + 1", model.send(:instance_variable_get, :@caller_binding))
      expect(result[:success]).to be true
      expect(result[:result]).to eq(2)
    end
  end

  describe "baseline methods (#9)" do
    it "records baseline methods at init" do
      expect(model.baseline_methods).to be_an(Array)
      expect(model.baseline_methods).to include(:inspect)
    end

    it "detects new methods after definition" do
      model.init
      submit(model, "def zzz_baseline_test; end")
      binding_obj = model.send(:instance_variable_get, :@caller_binding)
      current = binding_obj.eval("methods")
      new_methods = current - model.baseline_methods
      expect(new_methods).to include(:zzz_baseline_test)
    end
  end

  describe "WindowSizeMessage" do
    it "does not crash" do
      result = model.update(Bubbletea::WindowSizeMessage.new(width: 80, height: 24))
      expect_mvu_tuple(result)
    end
  end
end
