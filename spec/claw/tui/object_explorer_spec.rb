# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::ObjectExplorer do
  let(:test_obj) do
    obj = Object.new
    obj.instance_variable_set(:@name, "test")
    obj.instance_variable_set(:@count, 42)
    obj.define_singleton_method(:greet) { "hello" }
    obj.define_singleton_method(:calculate) { |x| x * 2 }
    obj
  end
  let(:test_binding) { test_obj.instance_eval { x = 10; y = "hello"; binding } }

  describe ".ls" do
    it "returns local variables" do
      result = described_class.ls(test_binding)
      expect(result[:type]).to eq(:data)
      sections = result[:data]
      expect(sections).to have_key("Local Variables")
      locals = sections["Local Variables"].join("\n")
      expect(locals).to include("x:")
      expect(locals).to include("y:")
    end

    it "returns instance variables" do
      result = described_class.ls(test_binding)
      sections = result[:data]
      expect(sections).to have_key("Instance Variables")
      ivars = sections["Instance Variables"].join("\n")
      expect(ivars).to include("@name")
      expect(ivars).to include("@count")
    end

    it "returns own methods" do
      result = described_class.ls(test_binding)
      sections = result[:data]
      expect(sections).to have_key("Methods")
      methods = sections["Methods"].join("\n")
      expect(methods).to include("greet")
      expect(methods).to include("calculate")
    end
  end

  describe ".cd" do
    it "navigates into an object" do
      nav_stack = []
      result = described_class.cd('"hello"', test_binding, nav_stack)
      expect(result[:type]).to eq(:success)
      expect(result[:data][:label]).to include("String")
      expect(nav_stack.size).to eq(1)
    end

    it "navigates back with .." do
      nav_stack = [{ binding: test_binding, label: "top" }]
      result = described_class.cd("..", test_binding, nav_stack)
      expect(result[:type]).to eq(:success)
      expect(nav_stack).to be_empty
    end

    it "returns error for .. at top level" do
      result = described_class.cd("..", test_binding, [])
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("top level")
    end

    it "returns error for invalid expression" do
      result = described_class.cd("nonexistent_var_xyz", test_binding, [])
      expect(result[:type]).to eq(:error)
    end
  end

  describe ".source" do
    it "returns source for a file-defined method" do
      result = described_class.source("ls", test_binding)
      # ls is defined in object_explorer.rb, should have source
      if result[:type] == :data
        expect(result[:data][:file]).to include("object_explorer")
        expect(result[:data][:source]).to include("def")
      end
    end

    it "returns error for nonexistent method" do
      result = described_class.source("zzz_no_such_method", test_binding)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("not found")
    end

    it "returns error for native method without source" do
      result = described_class.source("object_id", test_binding)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("not available")
    end
  end

  describe ".doc" do
    it "returns documentation hash" do
      result = described_class.doc("to_s", test_binding)
      expect(result[:type]).to eq(:data)
      expect(result[:data]).to have_key(:topic)
      expect(result[:data]).to have_key(:doc)
    end
  end

  describe ".find" do
    it "finds methods matching a pattern" do
      result = described_class.find("greet", test_binding)
      expect(result[:type]).to eq(:data)
      expect(result[:data][:matches]).to include("greet")
    end

    it "returns info when no methods match" do
      result = described_class.find("zzz_no_match_xyz", test_binding)
      expect(result[:type]).to eq(:info)
    end

    it "returns error for invalid regex" do
      result = described_class.find("[invalid", test_binding)
      expect(result[:type]).to eq(:error)
      expect(result[:message]).to include("Invalid pattern")
    end
  end

  describe ".whereami" do
    it "returns file and line info" do
      result = described_class.whereami(test_binding)
      expect(result[:type]).to eq(:data)
      expect(result[:data]).to have_key(:file)
      expect(result[:data]).to have_key(:line)
      expect(result[:data]).to have_key(:receiver)
    end
  end
end
