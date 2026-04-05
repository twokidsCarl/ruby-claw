# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Resources::BindingResource do
  # Create a binding with some local variables for testing.
  # We use eval to create a real binding with locals.
  def make_binding
    a = 42
    b = "hello"
    c = [1, 2, 3]
    binding
  end

  let(:test_binding) { make_binding }
  let(:resource) { described_class.new(test_binding) }

  describe "#initialize" do
    it "tracks serializable variables" do
      expect(resource.tracked.keys).to include("a", "b", "c")
    end

    it "excludes non-serializable variables" do
      b = binding
      b.local_variable_set(:io_obj, $stdout)

      excluded_names = []
      res = described_class.new(b, on_exclude: ->(name, _e) { excluded_names << name })

      expect(res.excluded.keys).to include("io_obj")
      expect(excluded_names).to include("io_obj")
    end
  end

  describe "#snapshot!" do
    it "returns a frozen hash of variable blobs" do
      token = resource.snapshot!
      expect(token).to be_frozen
      expect(token.keys).to include("a", "b", "c")
    end

    it "captures current values" do
      token = resource.snapshot!
      expect(MarshalMd.load(token["a"])).to eq(42)
      expect(MarshalMd.load(token["b"])).to eq("hello")
      expect(MarshalMd.load(token["c"])).to eq([1, 2, 3])
    end

    it "picks up new variables added after initialization" do
      test_binding.local_variable_set(:new_var, "fresh")
      token = resource.snapshot!
      expect(token.keys).to include("new_var")
      expect(MarshalMd.load(token["new_var"])).to eq("fresh")
    end

    it "returns deep copies (mutations don't affect snapshot)" do
      token = resource.snapshot!
      test_binding.local_variable_set(:a, 999)
      expect(MarshalMd.load(token["a"])).to eq(42)
    end
  end

  describe "#rollback!" do
    it "restores variable values" do
      token = resource.snapshot!

      test_binding.local_variable_set(:a, 999)
      test_binding.local_variable_set(:b, "changed")

      resource.rollback!(token)

      expect(test_binding.local_variable_get(:a)).to eq(42)
      expect(test_binding.local_variable_get(:b)).to eq("hello")
    end

    it "nils out variables that didn't exist in the snapshot" do
      token = resource.snapshot!

      test_binding.local_variable_set(:new_var, "extra")
      resource.scan_binding  # track the new var

      resource.rollback!(token)

      expect(test_binding.local_variable_get(:new_var)).to be_nil
    end

    it "handles complex types (Hash, nested Array)" do
      test_binding.local_variable_set(:data, { x: [1, { y: 2 }] })
      token = resource.snapshot!

      test_binding.local_variable_set(:data, { x: "replaced" })
      resource.rollback!(token)

      expect(test_binding.local_variable_get(:data)).to eq({ x: [1, { y: 2 }] })
    end
  end

  describe "#diff" do
    it "shows changed variables" do
      token_a = resource.snapshot!
      test_binding.local_variable_set(:a, 100)
      token_b = resource.snapshot!

      result = resource.diff(token_a, token_b)
      expect(result).to include("~ a: 42 → 100")
    end

    it "shows added variables" do
      token_a = resource.snapshot!
      test_binding.local_variable_set(:new_var, "added")
      token_b = resource.snapshot!

      result = resource.diff(token_a, token_b)
      expect(result).to include("+ new_var")
    end

    it "shows removed variables" do
      test_binding.local_variable_set(:temp, "gone")
      resource.scan_binding
      token_a = resource.snapshot!

      test_binding.local_variable_set(:temp, nil)
      # Simulate removal by creating a token without :temp
      token_b = resource.snapshot!
      token_b_without = token_b.reject { |k, _| k == "temp" }.freeze

      result = resource.diff(token_a, token_b_without)
      expect(result).to include("- temp")
    end

    it "returns no changes for identical snapshots" do
      token = resource.snapshot!
      expect(resource.diff(token, token)).to eq("(no changes)")
    end
  end

  describe "#to_md" do
    it "lists tracked variables with values" do
      md = resource.to_md
      expect(md).to include("tracked")
      expect(md).to include("`a`")
      expect(md).to include("42")
    end

    it "lists excluded variables" do
      test_binding.local_variable_set(:io_obj, $stdout)
      resource.scan_binding

      md = resource.to_md
      expect(md).to include("`io_obj`")
      expect(md).to include("excluded")
    end
  end

  describe "#scan_binding" do
    it "detects new variables" do
      expect(resource.tracked.keys).not_to include("fresh")

      test_binding.local_variable_set(:fresh, 123)
      resource.scan_binding

      expect(resource.tracked.keys).to include("fresh")
    end

    it "calls on_exclude for non-serializable values" do
      excluded = []
      res = described_class.new(test_binding, on_exclude: ->(name, _e) { excluded << name })

      test_binding.local_variable_set(:proc_var, -> { "hi" })
      res.scan_binding

      expect(excluded).to include("proc_var")
      expect(res.excluded.keys).to include("proc_var")
    end
  end
end
