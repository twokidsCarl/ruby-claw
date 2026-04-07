# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::Folding do
  describe ".fold_tool_calls" do
    it "preserves non-tool_call messages" do
      messages = [
        { role: :system, content: "ready" },
        { role: :user, content: "a + b" },
        { role: :ruby, content: "3" },
        { role: :user, content: "x" },
        { role: :ruby, content: "42" }
      ]
      result = described_class.fold_tool_calls(messages)
      expect(result).to eq(messages)
    end

    it "does not fold 2 or fewer tool calls" do
      messages = [
        { role: :tool_call, icon: "⚡", detail: "read_var(x)" },
        { role: :tool_call, icon: "⚡", detail: "read_var(y)" }
      ]
      result = described_class.fold_tool_calls(messages)
      expect(result).to eq(messages)
    end

    it "folds 3+ consecutive tool calls into summary" do
      messages = [
        { role: :user, content: "do stuff" },
        { role: :tool_call, icon: "⚡", detail: "read_var(a)" },
        { role: :tool_call, icon: "⚡", detail: "read_var(b)" },
        { role: :tool_call, icon: "⚡", detail: "read_var(c)" },
        { role: :ruby, content: "done" }
      ]
      result = described_class.fold_tool_calls(messages)
      expect(result.size).to eq(3) # user + folded_tool + ruby
      expect(result[0][:role]).to eq(:user)
      expect(result[1][:role]).to eq(:tool_call)
      expect(result[1][:folded]).to be true
      expect(result[2][:role]).to eq(:ruby)
    end

    it "preserves interleaved tool and non-tool messages" do
      messages = [
        { role: :user, content: "q1" },
        { role: :tool_call, icon: "⚡", detail: "read_var(x)" },
        { role: :tool_result, result: "42" },
        { role: :ruby, content: "42" },
        { role: :user, content: "q2" }
      ]
      result = described_class.fold_tool_calls(messages)
      expect(result.map { |m| m[:role] }).to eq(%i[user tool_call tool_result ruby user])
    end
  end
end
