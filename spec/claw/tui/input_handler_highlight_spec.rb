# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::InputHandler, ".highlight" do
  # Color short-hands for assertions
  MAGENTA = "\e[35m"
  CYAN    = "\e[36m"
  GREEN   = "\e[32m"
  YELLOW  = "\e[33m"
  BLUE    = "\e[34m"
  DIM     = "\e[2m"
  RESET   = "\e[0m"

  def highlight(code)
    described_class.highlight(code)
  end

  describe "keywords" do
    it "colors def/end magenta" do
      out = highlight("def foo\nend")
      expect(out).to include("#{MAGENTA}def#{RESET}")
      expect(out).to include("#{MAGENTA}end#{RESET}")
    end

    it "colors if/else/elsif/unless" do
      out = highlight("if x\nelsif y\nelse\nend")
      %w[if elsif else end].each do |kw|
        expect(out).to include("#{MAGENTA}#{kw}#{RESET}")
      end
    end

    it "colors begin/rescue/ensure" do
      out = highlight("begin\nrescue\nensure\nend")
      %w[begin rescue ensure end].each do |kw|
        expect(out).to include("#{MAGENTA}#{kw}#{RESET}")
      end
    end

    it "colors case/in patterns (Ruby 3.0+) — once a regex highlighter would miss this" do
      out = highlight("case x\nin 1\n  :a\nin 2\n  :b\nend")
      # `case` and `in` are real keywords in Ruby 3+; Ripper tags both as :on_kw
      expect(out).to include("#{MAGENTA}case#{RESET}")
      expect(out).to include("#{MAGENTA}in#{RESET}")
    end
  end

  describe "literals (true/false/nil/self) — cyan" do
    %w[true false nil self].each do |lit|
      it "colors #{lit} cyan" do
        expect(highlight("x = #{lit}")).to include("#{CYAN}#{lit}#{RESET}")
      end
    end
  end

  describe "strings" do
    it "colors double-quoted strings green" do
      out = highlight('x = "hello"')
      expect(out).to include(GREEN)
      expect(out).to include("hello")
    end

    it "colors single-quoted strings green" do
      out = highlight("x = 'hello'")
      expect(out).to include(GREEN)
    end

    it "does NOT misinterpret # inside a string as a comment" do
      # Old regex highlighter dimmed the entire rest of the line after #,
      # even when # was inside a string.
      out = highlight('puts "this # is not a comment"')
      # The DIM code should not engulf "is not a comment"
      expect(out).not_to match(/#{Regexp.escape(DIM)}is not a comment/)
    end
  end

  describe "numbers" do
    it "colors integers blue" do
      expect(highlight("x = 42")).to include("#{BLUE}42#{RESET}")
    end

    it "colors floats blue" do
      expect(highlight("x = 3.14")).to include("#{BLUE}3.14#{RESET}")
    end
  end

  describe "symbols" do
    it "colors :foo yellow" do
      out = highlight("x = :foo")
      expect(out).to include(YELLOW)
      expect(out).to include("foo")
    end

    it "colors hash-style symbols (foo:) yellow" do
      out = highlight("h = { foo: 1 }")
      expect(out).to include(YELLOW)
    end
  end

  describe "comments" do
    it "dims # comments" do
      out = highlight("x = 1 # this is a comment")
      expect(out).to include("#{DIM}# this is a comment#{RESET}")
    end
  end

  describe "constants" do
    it "colors capitalized constants cyan" do
      out = highlight("Klass.new")
      expect(out).to include("#{CYAN}Klass#{RESET}")
    end
  end

  describe "edge cases" do
    it "returns input unchanged for nil/empty" do
      expect(highlight(nil)).to be_nil
      expect(highlight("")).to eq("")
    end

    it "does not crash on syntactically incomplete code (real typing case)" do
      # Ripper.lex is fault-tolerant; this must work mid-keystroke.
      expect { highlight("def foo") }.not_to raise_error
      expect { highlight("if x &&") }.not_to raise_error
      expect { highlight('"unclosed') }.not_to raise_error
    end

    it "preserves the original string exactly when ANSI codes are stripped" do
      code = "def add(a, b); a + b; end"
      colored = highlight(code)
      stripped = colored.gsub(/\e\[[0-9;]*m/, "")
      expect(stripped).to eq(code)
    end

    it "handles string interpolation without breaking — old regex would split mid-#{}" do
      out = highlight('x = "hello #{name}"')
      # Output should still tokenize correctly; check we don't lose content
      stripped = out.gsub(/\e\[[0-9;]*m/, "")
      expect(stripped).to eq('x = "hello #{name}"')
    end
  end
end
