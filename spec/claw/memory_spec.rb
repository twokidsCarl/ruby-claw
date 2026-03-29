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

  describe "#remember" do
    it "logs to the daily log" do
      memory = described_class.new
      memory.remember("User prefers concise output")

      log_dir = File.join(tmpdir, "log")
      expect(Dir.exist?(log_dir)).to be(true)
      log_files = Dir.glob(File.join(log_dir, "*.md"))
      expect(log_files.size).to eq(1)
      content = File.read(log_files.first)
      expect(content).to include("Remembered")
      expect(content).to include("User prefers concise output")
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
    it "saves and loads session as Markdown" do
      Claw.configure { |c| c.persist_session = true }
      Mana.configure { |c| c.memory_path = tmpdir }

      memory = described_class.new
      memory.short_term << { role: "user", content: "Hello" }
      memory.short_term << { role: "assistant", content: "Hi there" }
      memory.save_session

      # Verify session.md was created
      session_path = File.join(tmpdir, "session.md")
      expect(File.exist?(session_path)).to be(true)
      content = File.read(session_path)
      expect(content).to include("# Session State")

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

RSpec.describe Claw::FileStore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:store) { described_class.new(tmpdir) }

  before do
    Mana.configure do |c|
      c.api_key = "test-key"
      c.memory_path = tmpdir
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe "#read / #write (MEMORY.md)" do
    it "writes and reads back memories in Markdown format" do
      memories = [
        { id: 1, content: "User prefers concise output", created_at: "2026-03-28" },
        { id: 2, content: "Project uses PostgreSQL 14", created_at: "2026-03-28" }
      ]
      store.write("default", memories)

      path = File.join(tmpdir, "MEMORY.md")
      expect(File.exist?(path)).to be(true)
      content = File.read(path)
      expect(content).to include("# Long-term Memory")
      expect(content).to include("## id:1 | 2026-03-28")
      expect(content).to include("User prefers concise output")
      expect(content).to include("## id:2 | 2026-03-28")

      result = store.read("default")
      expect(result.size).to eq(2)
      expect(result[0][:id]).to eq(1)
      expect(result[0][:content]).to eq("User prefers concise output")
      expect(result[0][:created_at]).to eq("2026-03-28")
      expect(result[1][:id]).to eq(2)
      expect(result[1][:content]).to eq("Project uses PostgreSQL 14")
    end

    it "returns empty array when MEMORY.md does not exist" do
      expect(store.read("default")).to eq([])
    end
  end

  describe "#clear" do
    it "deletes MEMORY.md" do
      store.write("default", [{ id: 1, content: "test", created_at: "2026-03-28" }])
      path = File.join(tmpdir, "MEMORY.md")
      expect(File.exist?(path)).to be(true)

      store.clear("default")
      expect(File.exist?(path)).to be(false)
    end
  end

  describe "#read_session / #write_session (session.md)" do
    it "writes and reads back session data in Markdown format" do
      data = { summaries: ["Analyzed stock portfolio, total was 438.4"], updated_at: "2026-03-29T10:30:00Z" }
      store.write_session("default", data)

      path = File.join(tmpdir, "session.md")
      expect(File.exist?(path)).to be(true)
      content = File.read(path)
      expect(content).to include("# Session State")
      expect(content).to include("## Summary")
      expect(content).to include("- Analyzed stock portfolio, total was 438.4")
      expect(content).to include("## Last Updated")
      expect(content).to include("2026-03-29T10:30:00Z")

      result = store.read_session("default")
      expect(result[:summaries]).to eq(["Analyzed stock portfolio, total was 438.4"])
    end

    it "returns nil when session.md does not exist" do
      expect(store.read_session("default")).to be_nil
    end
  end

  describe "#clear_session" do
    it "deletes session.md" do
      store.write_session("default", { summaries: ["test"] })
      path = File.join(tmpdir, "session.md")
      expect(File.exist?(path)).to be(true)

      store.clear_session("default")
      expect(File.exist?(path)).to be(false)
    end
  end

  describe "#append_log" do
    it "creates a daily log file and appends entries" do
      store.append_log(title: "Remembered", detail: "- User likes Ruby")

      log_dir = File.join(tmpdir, "log")
      expect(Dir.exist?(log_dir)).to be(true)

      date = Time.now.strftime("%Y-%m-%d")
      log_path = File.join(log_dir, "#{date}.md")
      expect(File.exist?(log_path)).to be(true)

      content = File.read(log_path)
      expect(content).to include("# #{date}")
      expect(content).to include("Remembered")
      expect(content).to include("User likes Ruby")
    end

    it "appends multiple entries to the same daily log" do
      store.append_log(title: "First", detail: "- detail one")
      store.append_log(title: "Second", detail: "- detail two")

      date = Time.now.strftime("%Y-%m-%d")
      log_path = File.join(tmpdir, "log", "#{date}.md")
      content = File.read(log_path)
      expect(content).to include("First")
      expect(content).to include("Second")
    end
  end
end
