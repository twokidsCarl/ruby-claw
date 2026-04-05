# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Init do
  let(:tmpdir) { Dir.mktmpdir("claw_init_test") }
  let(:claw_dir) { File.join(tmpdir, ".ruby-claw") }
  let(:output) { StringIO.new }

  after { FileUtils.rm_rf(tmpdir) }

  # Stub git clone to avoid network calls — create fake gem directories instead
  before do
    allow(Open3).to receive(:capture2e).and_wrap_original do |original, *args|
      if args.include?("clone")
        # Fake clone: create the target directory with a minimal gemspec
        target = args.last
        FileUtils.mkdir_p(target)
        File.write(File.join(target, "README.md"), "# fake gem\n")
        ["", instance_double(Process::Status, success?: true)]
      else
        original.call(*args)
      end
    end
  end

  describe ".run" do
    it "creates .ruby-claw/ directory" do
      described_class.run(dir: tmpdir, stdout: output)
      expect(Dir.exist?(claw_dir)).to be true
    end

    it "creates gems/ with ruby-claw and ruby-mana" do
      described_class.run(dir: tmpdir, stdout: output)
      expect(Dir.exist?(File.join(claw_dir, "gems", "ruby-claw"))).to be true
      expect(Dir.exist?(File.join(claw_dir, "gems", "ruby-mana"))).to be true
    end

    it "creates system_prompt.md" do
      described_class.run(dir: tmpdir, stdout: output)
      path = File.join(claw_dir, "system_prompt.md")
      expect(File.exist?(path)).to be true
      expect(File.read(path)).to include("System Prompt")
    end

    it "creates MEMORY.md" do
      described_class.run(dir: tmpdir, stdout: output)
      path = File.join(claw_dir, "MEMORY.md")
      expect(File.exist?(path)).to be true
      expect(File.read(path)).to include("Long-term Memory")
    end

    it "creates Gemfile with path references" do
      described_class.run(dir: tmpdir, stdout: output)
      path = File.join(tmpdir, "Gemfile")
      expect(File.exist?(path)).to be true
      content = File.read(path)
      expect(content).to include('path: ".ruby-claw/gems/ruby-claw"')
      expect(content).to include('path: ".ruby-claw/gems/ruby-mana"')
    end

    it "skips Gemfile if already exists" do
      File.write(File.join(tmpdir, "Gemfile"), "# existing\n")
      described_class.run(dir: tmpdir, stdout: output)
      expect(File.read(File.join(tmpdir, "Gemfile"))).to eq("# existing\n")
      expect(output.string).to include("Gemfile already exists")
    end

    it "initializes git in .ruby-claw/" do
      described_class.run(dir: tmpdir, stdout: output)
      expect(Dir.exist?(File.join(claw_dir, ".git"))).to be true
    end

    it "creates initial git commit" do
      described_class.run(dir: tmpdir, stdout: output)
      log, status = Open3.capture2e("git", "-C", claw_dir, "log", "--oneline")
      expect(status.success?).to be true
      expect(log).to include("claw init")
    end

    it "returns true on success" do
      result = described_class.run(dir: tmpdir, stdout: output)
      expect(result).to be true
    end

    it "returns false if .ruby-claw/ already exists with content" do
      FileUtils.mkdir_p(claw_dir)
      File.write(File.join(claw_dir, "existing.txt"), "hi")
      result = described_class.run(dir: tmpdir, stdout: output)
      expect(result).to be false
      expect(output.string).to include("already exists")
    end

    it "prints progress messages" do
      described_class.run(dir: tmpdir, stdout: output)
      expect(output.string).to include("cloning ruby-claw")
      expect(output.string).to include("cloning ruby-mana")
      expect(output.string).to include("system_prompt.md created")
      expect(output.string).to include("MEMORY.md created")
      expect(output.string).to include("git initialized")
      expect(output.string).to include("claw init complete")
    end
  end

  describe "clone failure" do
    before do
      allow(Open3).to receive(:capture2e).and_wrap_original do |original, *args|
        if args.include?("clone")
          ["fatal: repository not found", instance_double(Process::Status, success?: false)]
        else
          original.call(*args)
        end
      end
    end

    it "raises on clone failure" do
      expect {
        described_class.run(dir: tmpdir, stdout: output)
      }.to raise_error(/Failed to clone/)
    end
  end
end
