# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Memory do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    Claw.configure { |c| c.persist_session = false }
    Mana.configure do |c|
      c.api_key = "test-key"
      c.memory_path = tmpdir
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
      context = Mana::Context.current
      Claw.configure { |c| c.memory_keep_recent = 1 }

      # Add multiple conversation rounds to context
      6.times do |i|
        context.messages << { role: "user", content: "Question #{i}" }
        context.messages << { role: "assistant", content: "Answer #{i}" }
      end

      # Stub the LLM summarization call
      stub_anthropic_text_only("Summary of conversation")

      memory.compact!

      # Should have kept only the last round + compacted the rest
      user_messages = context.messages.select { |m| m[:role] == "user" && m[:content].is_a?(String) }
      expect(user_messages.size).to eq(1)
      expect(context.summaries.size).to eq(1)
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

    it "deduplicates identical content" do
      memory = described_class.new
      entry1 = memory.remember("same fact")
      entry2 = memory.remember("same fact")
      expect(entry1).to equal(entry2)
      expect(memory.long_term.size).to eq(1)
    end

    it "persists to disk immediately" do
      memory = described_class.new
      memory.remember("persisted fact")
      store = Mana.config.memory_store || Mana::FileStore.new(tmpdir)
      # Verify via new memory instance
      memory2 = described_class.new
      expect(memory2.long_term.size).to eq(1)
      expect(memory2.long_term.first[:content]).to eq("persisted fact")
    end
  end

  describe "#forget" do
    it "removes a specific long-term memory by ID" do
      memory = described_class.new
      memory.remember("keep this")
      memory.remember("forget this")
      memory.forget(id: 2)
      expect(memory.long_term.size).to eq(1)
      expect(memory.long_term.first[:content]).to eq("keep this")
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
      context = Mana::Context.current
      context.messages << { role: "user", content: "Hello" }
      context.messages << { role: "assistant", content: "Hi there" }
      memory.save_session

      # Verify session.md was created
      session_path = File.join(tmpdir, "session.md")
      expect(File.exist?(session_path)).to be(true)
      content = File.read(session_path)
      expect(content).to include("# Session State")

      # Create a new context + memory and verify session loaded
      Thread.current[:mana_context] = nil
      Thread.current[:claw_memory] = nil
      Claw.configure { |c| c.persist_session = true }
      memory2 = described_class.new
      context2 = Mana::Context.current
      expect(context2.messages.size).to eq(2)
      expect(context2.messages.first[:content]).to eq("Hello")
    end
  end

  describe "#clear!" do
    it "clears session data as well" do
      Claw.configure { |c| c.persist_session = true }
      Mana.configure { |c| c.memory_path = tmpdir }

      memory = described_class.new
      context = Mana::Context.current
      context.messages << { role: "user", content: "Hello" }
      memory.save_session
      memory.clear!

      # Verify session file is also cleared
      Thread.current[:mana_context] = nil
      Thread.current[:claw_memory] = nil
      memory2 = described_class.new
      context2 = Mana::Context.current
      expect(context2.messages).to be_empty
    end
  end

  describe "Claw::Memory.current" do
    it "returns a Claw::Memory instance" do
      expect(described_class.current).to be_a(Claw::Memory)
    end

    it "is separate from Mana::Context.current" do
      claw_mem = described_class.current
      mana_ctx = Mana::Context.current
      expect(claw_mem).not_to equal(mana_ctx)
      expect(mana_ctx).to be_a(Mana::Context)
    end

    it "returns nil in incognito mode" do
      Claw::Memory.incognito do
        expect(described_class.current).to be_nil
      end
    end
  end

  describe "remember tool registration" do
    it "registers remember tool in Mana" do
      names = Mana.registered_tools.map { |t| t[:name] }
      expect(names).to include("remember")
    end

    it "remember tool handler stores to Claw memory" do
      handler = Mana.tool_handlers["remember"]
      expect(handler).not_to be_nil

      result = handler.call({ "content" => "test fact" })
      expect(result).to include("Remembered")

      memory = Claw.memory
      expect(memory.long_term.size).to eq(1)
      expect(memory.long_term.first[:content]).to eq("test fact")
    end
  end

  describe "prompt section registration" do
    it "injects long-term memories into prompt" do
      memory = described_class.current
      memory.remember("User likes Ruby")

      sections = Mana.prompt_sections.map(&:call).compact
      combined = sections.join("\n")
      expect(combined).to include("Long-term memories")
      expect(combined).to include("User likes Ruby")
    end
  end

  describe "#token_count" do
    it "counts long-term memories" do
      memory = described_class.new
      memory.remember("a fact to remember")
      expect(memory.token_count).to be > 0
    end

    it "includes context messages in count" do
      memory = described_class.new
      context = Mana::Context.current
      context.messages << { role: "user", content: "hello world" }
      expect(memory.token_count).to be > 0
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
