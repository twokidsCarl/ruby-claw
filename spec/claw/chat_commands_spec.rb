# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Chat slash commands" do
  # Test handle_slash_command via the class method directly.
  # We set up a runtime on the Chat module's @runtime class instance variable.

  let(:runtime) { Claw::Runtime.new }
  let(:test_resource_class) do
    Class.new do
      include Claw::Resource
      attr_accessor :value
      def initialize(v = 0) = @value = v
      def snapshot! = @value
      def rollback!(token) = @value = token
      def diff(a, b) = "#{a} → #{b}"
      def to_md = "value=#{@value}"
    end
  end

  before do
    resource = test_resource_class.new(10)
    runtime.register("test", resource)
    Claw::Chat.instance_variable_set(:@runtime, runtime)
  end

  after do
    Claw::Chat.instance_variable_set(:@runtime, nil)
  end

  def run_cmd(input)
    output = StringIO.new
    $stdout = output
    Claw::Chat.send(:handle_slash_command, input)
    $stdout = STDOUT
    output.string
  end

  describe "/snapshot" do
    it "creates a snapshot" do
      output = run_cmd("/snapshot test_label")
      expect(output).to include("snapshot #1")
      expect(output).to include("test_label")
      expect(runtime.snapshots.size).to eq(1)
    end

    it "works without a label" do
      output = run_cmd("/snapshot")
      expect(output).to include("snapshot #1")
    end
  end

  describe "/rollback" do
    it "rolls back to a snapshot" do
      resource = runtime.resources["test"]
      runtime.snapshot!(label: "before")
      resource.value = 99

      output = run_cmd("/rollback 1")
      expect(output).to include("rolled back")
      expect(resource.value).to eq(10)
    end

    it "shows usage without id" do
      output = run_cmd("/rollback")
      expect(output).to include("Usage")
    end
  end

  describe "/history" do
    it "lists snapshots" do
      runtime.snapshot!(label: "first")
      runtime.snapshot!(label: "second")

      output = run_cmd("/history")
      expect(output).to include("#1")
      expect(output).to include("first")
      expect(output).to include("#2")
      expect(output).to include("second")
    end

    it "shows message when no snapshots" do
      output = run_cmd("/history")
      expect(output).to include("No snapshots")
    end
  end

  describe "/diff" do
    it "diffs the last two snapshots by default" do
      runtime.snapshot!(label: "a")
      runtime.resources["test"].value = 42
      runtime.snapshot!(label: "b")

      output = run_cmd("/diff")
      expect(output).to include("10 → 42")
    end

    it "diffs specific snapshot ids" do
      runtime.snapshot!
      runtime.resources["test"].value = 42
      runtime.snapshot!

      output = run_cmd("/diff 1 2")
      expect(output).to include("10 → 42")
    end
  end

  describe "/status" do
    it "renders runtime state" do
      runtime.snapshot!(label: "init")
      output = run_cmd("/status")
      expect(output).to include("Runtime State")
      expect(output).to include("test")
    end
  end

  describe "unknown command" do
    it "shows available commands" do
      output = run_cmd("/unknown")
      expect(output).to include("Unknown command")
      expect(output).to include("/snapshot")
    end
  end
end
