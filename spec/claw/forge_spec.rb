# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Forge do
  include AnthropicHelper

  before do
    Mana.configure { |c| c.api_key = "test-key-000" }
  end

  let(:claw_dir) { Dir.mktmpdir("claw-forge-") }
  after { FileUtils.rm_rf(claw_dir) }

  describe ".promote" do
    let(:caller_binding) do
      obj = Object.new
      obj.instance_variable_set(:@__claw_definitions__, {
        "double_it" => "def double_it(x)\n  x * 2\nend"
      })
      obj.instance_eval { binding }
    end

    it "returns error when method not found" do
      result = described_class.promote("nonexistent", binding: caller_binding, claw_dir: claw_dir)
      expect(result[:success]).to be false
      expect(result[:message]).to include("not found")
    end

    it "creates a tool file from a tracked definition" do
      # Stub LLM to return a valid tool class (text-only, no tools)
      stub_anthropic_text_only(<<~RUBY)
        ```ruby
        class DoubleIt
          include Claw::Tool
          tool_name   "double_it"
          description "Double a number"
          parameter   :x, type: "Integer", required: true, desc: "Number to double"
          def call(x:)
            x * 2
          end
        end
        ```
      RUBY

      result = described_class.promote("double_it", binding: caller_binding, claw_dir: claw_dir)
      expect(result[:success]).to be true
      expect(result[:path]).to end_with("double_it.rb")
      expect(File.exist?(result[:path])).to be true
    end

    it "creates the tools directory if missing" do
      tools_dir = File.join(claw_dir, "tools")
      expect(Dir.exist?(tools_dir)).to be false

      stub_anthropic_text_only("class X\n  include Claw::Tool\n  tool_name 'x'\n  def call; end\nend")
      described_class.promote("double_it", binding: caller_binding, claw_dir: claw_dir)

      expect(Dir.exist?(tools_dir)).to be true
    end
  end

  describe "source finding" do
    it "reads from @__claw_definitions__" do
      obj = Object.new
      obj.instance_variable_set(:@__claw_definitions__, { "greet" => "def greet(name); end" })
      b = obj.instance_eval { binding }

      source = described_class.send(:find_source, "greet", b)
      expect(source).to eq("def greet(name); end")
    end

    it "returns nil when no definitions exist" do
      b = Object.new.instance_eval { binding }
      source = described_class.send(:find_source, "missing", b)
      expect(source).to be_nil
    end
  end

  describe "code extraction" do
    it "extracts from ```ruby blocks" do
      text = "Here's the code:\n```ruby\nclass Foo; end\n```\nDone."
      code = described_class.send(:extract_ruby_code, text)
      expect(code).to eq("class Foo; end")
    end

    it "detects bare class definitions" do
      text = "class Foo\n  def call; end\nend"
      code = described_class.send(:extract_ruby_code, text)
      expect(code).to eq(text)
    end

    it "returns nil for non-code text" do
      code = described_class.send(:extract_ruby_code, "just some text")
      expect(code).to be_nil
    end
  end
end
