# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Evolution do
  let(:tmpdir) { Dir.mktmpdir("claw_evo_test") }
  let(:claw_dir) { File.join(tmpdir, ".ruby-claw") }
  let(:gems_dir) { File.join(claw_dir, "gems") }
  let(:traces_dir) { File.join(claw_dir, "traces") }

  let(:runtime) do
    rt = Claw::Runtime.new
    # Register a minimal context resource for fork to work
    ctx = Mana::Context.new
    rt.register("context", Claw::Resources::ContextResource.new(ctx))
    rt.snapshot!(label: "init")
    rt
  end

  let(:evolution) do
    described_class.new(runtime: runtime, claw_dir: claw_dir)
  end

  before do
    Mana.config.api_key = "test-key"
    FileUtils.mkdir_p(traces_dir)
    FileUtils.mkdir_p(gems_dir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  # Helper to create a trace file
  def create_trace(name, content)
    File.write(File.join(traces_dir, "#{name}.md"), content)
  end

  # Helper to create a fake gem with a source file
  def create_gem_file(gem_name, relative_path, content)
    path = File.join(gems_dir, gem_name, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  describe "#load_recent_traces" do
    it "returns empty array when no traces" do
      expect(evolution.load_recent_traces).to eq([])
    end

    it "loads trace files sorted by mtime" do
      create_trace("trace1", "# Trace 1")
      sleep 0.01
      create_trace("trace2", "# Trace 2")

      traces = evolution.load_recent_traces
      expect(traces.size).to eq(2)
      expect(traces.last).to include("Trace 2")
    end

    it "limits to N most recent traces" do
      6.times { |i| create_trace("trace#{i}", "# Trace #{i}"); sleep 0.01 }

      traces = evolution.load_recent_traces(limit: 3)
      expect(traces.size).to eq(3)
    end
  end

  describe "#diagnose" do
    it "parses a valid proposal from LLM response" do
      proposal_json = JSON.generate({
        summary: "Improve error handling",
        gem: "ruby-claw",
        file: "lib/claw/chat.rb",
        old_code: "rescue => e",
        new_code: "rescue StandardError => e",
        rationale: "More specific error handling"
      })

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "text", text: proposal_json }],
            usage: { input_tokens: 100, output_tokens: 50 }
          })
        )

      result = evolution.diagnose(["# Trace 1\nsome trace"])
      expect(result[:summary]).to eq("Improve error handling")
      expect(result[:gem]).to eq("ruby-claw")
      expect(result[:file]).to eq("lib/claw/chat.rb")
    end

    it "handles 'no changes needed' response" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "text", text: '{"summary": "no changes needed"}' }],
            usage: { input_tokens: 100, output_tokens: 10 }
          })
        )

      result = evolution.diagnose(["# Trace"])
      expect(result[:summary]).to eq("no changes needed")
      expect(result[:file]).to be_nil
    end

    it "handles malformed JSON gracefully" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "text", text: "not json at all" }],
            usage: { input_tokens: 10, output_tokens: 5 }
          })
        )

      result = evolution.diagnose(["# Trace"])
      expect(result[:summary]).to include("no JSON")
    end
  end

  describe "#evolve" do
    it "skips when no traces exist" do
      FileUtils.rm_rf(traces_dir)
      result = evolution.evolve
      expect(result[:status]).to eq(:skip)
      expect(result[:reason]).to include("no traces")
    end

    it "skips when no gems/ directory exists" do
      FileUtils.rm_rf(gems_dir)
      create_trace("trace1", "# Trace")
      result = evolution.evolve
      expect(result[:status]).to eq(:skip)
      expect(result[:reason]).to include("gems/")
    end

    it "skips when LLM says no changes needed" do
      create_trace("trace1", "# Trace data")

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "text", text: '{"summary": "no changes needed"}' }],
            usage: { input_tokens: 10, output_tokens: 5 }
          })
        )

      result = evolution.evolve
      expect(result[:status]).to eq(:skip)
    end
  end

  describe "#try_proposal" do
    let(:proposal) do
      {
        summary: "Improve truncate",
        gem: "ruby-claw",
        file: "lib/claw/helper.rb",
        old_code: "str[0, max]",
        new_code: "str[0, max - 3]",
        rationale: "Leave room for ellipsis"
      }
    end

    it "rejects when file not found" do
      result = evolution.try_proposal(proposal)
      expect(result[:status]).to eq(:reject)
      expect(result[:reason]).to include("file not found")
    end

    it "rejects when old_code not found in file" do
      create_gem_file("ruby-claw", "lib/claw/helper.rb", "# different content\n")
      result = evolution.try_proposal(proposal)
      expect(result[:status]).to eq(:reject)
      expect(result[:reason]).to include("old_code not found")
    end

    it "accepts when change applied and tests pass" do
      source = "def truncate(str, max)\n  str[0, max] + '...'\nend\n"
      create_gem_file("ruby-claw", "lib/claw/helper.rb", source)
      create_gem_file("ruby-claw", "Gemfile", "source 'https://rubygems.org'\n")

      # Stub Open3.capture2e for test runner
      allow(Open3).to receive(:capture2e).and_return(
        ["10 examples, 0 failures", instance_double(Process::Status, success?: true)]
      )

      result = evolution.try_proposal(proposal)
      expect(result[:status]).to eq(:accept)
    end

    it "rejects when tests fail" do
      source = "def truncate(str, max)\n  str[0, max] + '...'\nend\n"
      create_gem_file("ruby-claw", "lib/claw/helper.rb", source)
      create_gem_file("ruby-claw", "Gemfile", "source 'https://rubygems.org'\n")

      # Stub Open3.capture2e for failing tests
      allow(Open3).to receive(:capture2e).and_return(
        ["1 example, 1 failure", instance_double(Process::Status, success?: false)]
      )

      result = evolution.try_proposal(proposal)
      expect(result[:status]).to eq(:reject)
      expect(result[:reason]).to include("tests failed")
    end

    it "rolls back file changes when tests fail (with FilesystemResource)" do
      source = "def truncate(str, max)\n  str[0, max] + '...'\nend\n"
      create_gem_file("ruby-claw", "lib/claw/helper.rb", source)
      create_gem_file("ruby-claw", "Gemfile", "source 'https://rubygems.org'\n")

      # Set up a runtime with FilesystemResource for full rollback
      fs_runtime = Claw::Runtime.new
      ctx = Mana::Context.new
      fs_runtime.register("context", Claw::Resources::ContextResource.new(ctx))
      fs_runtime.register("filesystem", Claw::Resources::FilesystemResource.new(claw_dir))
      fs_runtime.snapshot!(label: "init")

      evo = described_class.new(runtime: fs_runtime, claw_dir: claw_dir)

      allow(Open3).to receive(:capture2e).and_return(
        ["1 failure", instance_double(Process::Status, success?: false)]
      )

      evo.try_proposal(proposal)

      # File should be rolled back by FilesystemResource
      current = File.read(File.join(gems_dir, "ruby-claw", "lib/claw/helper.rb"))
      expect(current).to include("str[0, max]")
      expect(current).not_to include("str[0, max - 3]")
    end

    it "writes evolution log on accept" do
      source = "def truncate(str, max)\n  str[0, max] + '...'\nend\n"
      create_gem_file("ruby-claw", "lib/claw/helper.rb", source)
      create_gem_file("ruby-claw", "Gemfile", "source 'https://rubygems.org'\n")

      allow(Open3).to receive(:capture2e).and_return(
        ["ok", instance_double(Process::Status, success?: true)]
      )

      evolution.try_proposal(proposal)

      log_dir = File.join(claw_dir, "evolution")
      logs = Dir.glob(File.join(log_dir, "*_accept.md"))
      expect(logs.size).to eq(1)
      expect(File.read(logs.first)).to include("Improve truncate")
    end
  end
end
