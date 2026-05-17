# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::RubyTextArea do
  let(:ta) do
    t = described_class.new(width: 40, height: 3)
    t.prompt = ">> "
    t.prompt_style = Lipgloss::Style.new.foreground("#00BFFF")
    t.focus
    t
  end

  describe "syntax highlighting in view" do
    it "highlights keywords" do
      ta.value = "def foo"
      output = ta.view
      # Should contain ANSI magenta escape for 'def'
      expect(output).to include("\e[35mdef\e[0m")
    end

    it "highlights strings" do
      ta.value = 'x = "hello"'
      output = ta.view
      expect(output).to include("\e[32m")
    end

    it "highlights numbers" do
      ta.value = "x = 42"
      output = ta.view
      expect(output).to include("\e[34m42\e[0m")
    end

    it "highlights symbols" do
      ta.value = "x = :foo"
      output = ta.view
      # Ripper tokenizes :foo as two tokens (:on_symbeg ":" + :on_ident "foo");
      # both are colored yellow so the visual result is identical to a single
      # contiguous span. Check the parts independently to stay tokenizer-
      # implementation-agnostic.
      expect(output).to include("\e[33m:\e[0m")
      expect(output).to match(/\e\[33m:?\e\[0m.{0,3}\e\[33mfoo\e\[0m/) # `:` then `foo` both yellow
    end

    it "highlights boolean literals" do
      ta.value = "x = true"
      output = ta.view
      expect(output).to include("\e[36mtrue\e[0m")
    end

    it "renders plain text without errors" do
      ta.value = "hello"
      output = ta.view
      expect(output).to include("hello")
    end

    it "handles multi-line content" do
      ta.value = "def bar\n  42\nend"
      ta.show_line_numbers = true
      output = ta.view
      expect(output).to include("\e[35mdef\e[0m")
      expect(output).to include("\e[34m42\e[0m")
      expect(output).to include("\e[35mend\e[0m")
    end
  end
end
