# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Memory do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    Claw.configure { |c| c.persist_session = false }
    Mana.configure do |c|
      c.api_key = "test-key"
      c.memory_path = tmpdir
      c.memory_class = Claw::Memory
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe "#needs_compaction?" do
    it "returns false when token count is below threshold" do
      memory = described_class.new
      expect(memory.needs_compaction?).to be(false)
    end

    it "returns true when token count exceeds threshold" do
      memory = described_class.new
      Mana.configure { |c| c.context_window = 100 }
      Claw.configure { |c| c.memory_pressure = 0.01 }
      # Add enough content to exceed 1 token (threshold = 100 * 0.01 = 1)
      memory.remember("some content to push over the threshold")
      expect(memory.needs_compaction?).to be(true)
    end
  end

  describe "#compact!" do
    it "summarizes old messages and keeps recent rounds" do
      memory = described_class.new
      Claw.configure { |c| c.memory_keep_recent = 1 }

      # Add multiple conversation rounds
      6.times do |i|
        memory.short_term << { role: "user", content: "Question #{i}" }
        memory.short_term << { role: "assistant", content: "Answer #{i}" }
      end

      # Stub the LLM summarization call
      stub_anthropic_text_only("Summary of conversation")

      memory.compact!

      # Should have kept only the last round + compacted the rest
      user_messages = memory.short_term.select { |m| m[:role] == "user" && m[:content].is_a?(String) }
      expect(user_messages.size).to eq(1)
      expect(memory.summaries.size).to eq(1)
    end
  end

  describe "#search" do
    it "finds memories matching keywords" do
      memory = described_class.new
      memory.remember("Ruby is a great programming language")
      memory.remember("Python is also popular")
      memory.remember("Ruby on Rails is a web framework")

      results = memory.search("Ruby")
      expect(results.size).to eq(2)
      expect(results.map { |r| r[:content] }).to all(include("Ruby"))
    end

    it "returns empty for no matches" do
      memory = described_class.new
      memory.remember("Ruby is great")

      results = memory.search("JavaScript")
      expect(results).to be_empty
    end

    it "respects top_k limit" do
      memory = described_class.new
      5.times { |i| memory.remember("Ruby fact #{i}") }

      results = memory.search("Ruby", top_k: 2)
      expect(results.size).to eq(2)
    end
  end

  describe "session persistence" do
    it "saves and loads session" do
      Claw.configure { |c| c.persist_session = true }
      Mana.configure { |c| c.memory_path = tmpdir }

      memory = described_class.new
      memory.short_term << { role: "user", content: "Hello" }
      memory.short_term << { role: "assistant", content: "Hi there" }
      memory.save_session

      # Create a new memory instance and verify session loaded
      Claw.configure { |c| c.persist_session = true }
      memory2 = described_class.new
      expect(memory2.short_term.size).to eq(2)
      expect(memory2.short_term.first[:content]).to eq("Hello")
    end
  end

  describe "#clear!" do
    it "clears session data as well" do
      Claw.configure { |c| c.persist_session = true }
      Mana.configure { |c| c.memory_path = tmpdir }

      memory = described_class.new
      memory.short_term << { role: "user", content: "Hello" }
      memory.save_session
      memory.clear!

      # Verify session file is also cleared
      memory2 = described_class.new
      expect(memory2.short_term).to be_empty
    end
  end

  describe "Mana::Memory.current integration" do
    it "returns a Claw::Memory instance" do
      expect(Mana::Memory.current).to be_a(Claw::Memory)
    end

    it "returns nil in incognito mode" do
      Mana::Memory.incognito do
        expect(Mana::Memory.current).to be_nil
      end
    end
  end
end
