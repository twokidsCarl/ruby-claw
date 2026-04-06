# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Tool do
  let(:tool_class) do
    Class.new do
      include Claw::Tool

      tool_name   "test_tool"
      description "A test tool for specs"
      parameter   :input,  type: "String",  required: true,  desc: "The input value"
      parameter   :count,  type: "Integer", required: false, desc: "Repeat count"
      parameter   :config, type: "Hash",    required: false, desc: "Configuration"

      def call(input:, count: 1, config: {})
        "#{input} x #{count}"
      end
    end
  end

  describe "DSL methods" do
    it "stores tool_name" do
      expect(tool_class.tool_name).to eq("test_tool")
    end

    it "stores description" do
      expect(tool_class.description).to eq("A test tool for specs")
    end

    it "stores parameters" do
      params = tool_class.tool_parameters
      expect(params.size).to eq(3)
      expect(params[0][:name]).to eq(:input)
      expect(params[0][:required]).to be true
      expect(params[1][:name]).to eq(:count)
      expect(params[1][:required]).to be false
    end
  end

  describe ".to_tool_definition" do
    let(:definition) { tool_class.to_tool_definition }

    it "returns a Mana-compatible hash" do
      expect(definition[:name]).to eq("test_tool")
      expect(definition[:description]).to eq("A test tool for specs")
      expect(definition[:input_schema]).to be_a(Hash)
    end

    it "maps Ruby types to JSON schema types" do
      schema = definition[:input_schema]
      expect(schema[:properties]["input"][:type]).to eq("string")
      expect(schema[:properties]["count"][:type]).to eq("integer")
      expect(schema[:properties]["config"][:type]).to eq("object")
    end

    it "lists required parameters" do
      expect(definition[:input_schema][:required]).to eq(["input"])
    end
  end

  describe "#call" do
    it "executes the tool with keyword args" do
      result = tool_class.new.call(input: "hello", count: 3)
      expect(result).to eq("hello x 3")
    end

    it "uses default values for optional params" do
      result = tool_class.new.call(input: "hello")
      expect(result).to eq("hello x 1")
    end
  end

  describe "default tool_name inference" do
    let(:unnamed_class) do
      # Anonymous class — tool_name falls back to nil-safe handling
      Class.new do
        include Claw::Tool
        description "unnamed"
      end
    end

    it "returns nil for anonymous classes" do
      # Anonymous classes have nil name, so tool_name is nil
      expect(unnamed_class.tool_name).to be_nil
    end
  end
end
