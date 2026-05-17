# frozen_string_literal: true

require "spec_helper"

# Edge-case tests for the medium-batch fixes:
# - chat_history pruning
# - RubyTextArea encapsulated mutations
# - serializer atomic write

RSpec.describe "Claw::TUI::Model chat_history pruning" do
  let(:test_binding) { Object.new.instance_eval { x = 42; binding } }
  let(:model) { Claw::TUI::Model.new(test_binding) }

  it "keeps history when below the cap" do
    100.times { |i| model.chat_history << { role: :user, content: "msg #{i}" } }
    model.update(Bubbletea::Message.new)
    expect(model.chat_history.size).to eq(100)
  end

  it "trims to cap and inserts a marker when above the cap" do
    max = Claw::TUI::Model::CHAT_HISTORY_MAX
    chunk = Claw::TUI::Model::CHAT_HISTORY_TRIM_CHUNK
    (max + 50).times { |i| model.chat_history << { role: :user, content: "msg #{i}" } }
    expect(model.chat_history.size).to be > max

    model.update(Bubbletea::Message.new)

    # After pruning: (max + 50) - chunk old + 1 marker
    expected = (max + 50) - chunk + 1
    expect(model.chat_history.size).to eq(expected)
    expect(model.chat_history.first[:role]).to eq(:system)
    expect(model.chat_history.first[:content]).to include("trimmed")
  end
end

RSpec.describe Claw::TUI::RubyTextArea do
  let(:ta) do
    t = described_class.new(width: 40, height: 3)
    t.focus
    t
  end

  describe "#indent_current_line" do
    it "inserts spaces at start of current row and moves cursor" do
      ta.value = "def foo\n"
      ta.indent_current_line("  ")
      lines = ta.instance_variable_get(:@lines)
      expect(lines[ta.row]).to start_with("  ")
      expect(ta.col).to eq(2)
    end
  end

  describe "#current_line_is_lone_end?" do
    it "returns true for whitespace + end" do
      ta.value = "def foo\n    end"
      expect(ta.current_line_is_lone_end?).to be true
    end

    it "returns false for end with trailing content" do
      ta.value = "def foo\n    end if x"
      expect(ta.current_line_is_lone_end?).to be false
    end

    it "returns false for non-end content" do
      ta.value = "def foo\n  body"
      expect(ta.current_line_is_lone_end?).to be false
    end
  end

  describe "#dedent_current_line" do
    it "strips 2 leading spaces and adjusts cursor" do
      ta.value = "def foo\n    end"
      result = ta.dedent_current_line(2)
      expect(result).to be true
      lines = ta.instance_variable_get(:@lines)
      expect(lines[ta.row]).to eq("  end")
    end

    it "returns false when there is nothing to dedent" do
      ta.value = "end"
      result = ta.dedent_current_line(2)
      expect(result).to be false
    end
  end
end

RSpec.describe "Claw::Serializer atomic write" do
  let(:dir) { Dir.mktmpdir("claw-atomic-") }
  after { FileUtils.rm_rf(dir) }

  it "leaves the target file intact if write is interrupted" do
    # Pre-populate with valid JSON
    path = File.join(dir, "values.json")
    File.write(path, '{"existing": {"type": "marshal_md", "data": "42"}}')
    pre_content = File.read(path)

    # Stub File.rename to simulate an OS-level interruption AFTER the tmp
    # file is written but BEFORE the rename completes.
    allow(File).to receive(:rename).and_raise(Errno::EACCES, "interrupted")

    bind = Object.new.instance_eval { x = 99; binding }
    expect { Claw::Serializer.save(bind, dir) }.to raise_error(Errno::EACCES)

    # Original values.json must be unchanged — atomic write's whole point.
    expect(File.read(path)).to eq(pre_content)
  end

  it "writes the new content visibly only after rename succeeds" do
    bind = Object.new.instance_eval { x = 7; binding }
    Claw::Serializer.save(bind, dir)
    expect(File.exist?(File.join(dir, "values.json"))).to be true
    # No leftover .tmp files
    expect(Dir.glob(File.join(dir, "*.tmp.*"))).to be_empty
  end
end

RSpec.describe "Claw::TUI::ChatPanel tool result expand" do
  it "preserves the full result in :folded_full when truncated" do
    big = "x" * 500
    messages = [{ role: :tool_result, result: big }]
    described_class.send(:render_messages, messages, 70) if false # warm constant
    Claw::TUI::ChatPanel.send(:render_messages, messages, 70)
    expect(messages.first[:folded_full]).to eq(big)
  end

  it "does not set :folded_full for small results" do
    messages = [{ role: :tool_result, result: "ok" }]
    Claw::TUI::ChatPanel.send(:render_messages, messages, 70)
    expect(messages.first[:folded_full]).to be_nil
  end
end
