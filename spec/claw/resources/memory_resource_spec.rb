# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Resources::MemoryResource do
  let(:tmpdir) { Dir.mktmpdir }
  let(:memory) do
    # Configure store to use tmpdir so we can verify disk sync
    Mana.config.memory_path = tmpdir
    Claw::Memory.new
  end
  let(:resource) { described_class.new(memory) }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#snapshot!" do
    it "captures the long_term array" do
      memory.remember("fact 1")
      memory.remember("fact 2")

      token = resource.snapshot!
      expect(token.size).to eq(2)
      expect(token.first[:content]).to eq("fact 1")
    end

    it "returns a deep copy" do
      memory.remember("original")
      token = resource.snapshot!

      memory.remember("new fact")
      expect(token.size).to eq(1)
    end
  end

  describe "#rollback!" do
    it "restores long_term array" do
      memory.remember("keep this")
      token = resource.snapshot!

      memory.remember("remove this")
      expect(memory.long_term.size).to eq(2)

      resource.rollback!(token)
      expect(memory.long_term.size).to eq(1)
      expect(memory.long_term.first[:content]).to eq("keep this")
    end

    it "syncs restored state to disk" do
      memory.remember("keep this")
      token = resource.snapshot!

      memory.remember("remove this")
      resource.rollback!(token)

      # Verify by reading from a fresh store using the same store type
      ns = memory.send(:namespace)
      fresh_store = Mana::FileStore.new(tmpdir)
      on_disk = fresh_store.read(ns)
      expect(on_disk.size).to eq(1)
      expect(on_disk.first[:content]).to eq("keep this")
    end

    it "handles rollback to empty state" do
      token = resource.snapshot!
      memory.remember("temporary")

      resource.rollback!(token)
      expect(memory.long_term).to be_empty
    end
  end

  describe "#diff" do
    it "shows added memories" do
      token_a = resource.snapshot!
      memory.remember("new fact")
      token_b = resource.snapshot!

      result = resource.diff(token_a, token_b)
      expect(result).to include("+ [1] new fact")
    end

    it "shows removed memories" do
      memory.remember("old fact")
      token_a = resource.snapshot!
      memory.forget(id: 1)
      token_b = resource.snapshot!

      result = resource.diff(token_a, token_b)
      expect(result).to include("- [1] old fact")
    end

    it "returns no changes for identical snapshots" do
      memory.remember("stable fact")
      token_a = resource.snapshot!
      token_b = resource.snapshot!

      expect(resource.diff(token_a, token_b)).to eq("(no changes)")
    end
  end

  describe "#to_md" do
    it "shows empty state" do
      expect(resource.to_md).to eq("(empty)")
    end

    it "lists memories" do
      memory.remember("fact 1")
      memory.remember("fact 2")

      md = resource.to_md
      expect(md).to include("2 memories:")
      expect(md).to include("- [1] fact 1")
      expect(md).to include("- [2] fact 2")
    end
  end
end
