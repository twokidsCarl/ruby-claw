# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Resources::FilesystemResource do
  let(:tmpdir) { Dir.mktmpdir("claw-fs-test") }
  let(:resource) { described_class.new(tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#initialize" do
    it "initializes a git repo in the directory" do
      resource # trigger lazy let
      expect(File.directory?(File.join(tmpdir, ".git"))).to be true
    end

    it "creates an initial commit" do
      resource # trigger lazy let
      log = `git -C #{tmpdir} log --oneline 2>&1`.strip
      expect(log).to include("init")
    end

    it "does not re-init if git already exists" do
      resource # trigger lazy let
      described_class.new(tmpdir)
      log = `git -C #{tmpdir} log --oneline 2>&1`
      expect(log.lines.count { |l| l.include?("init") }).to eq(1)
    end
  end

  describe "#snapshot!" do
    it "returns a commit SHA" do
      File.write(File.join(tmpdir, "test.txt"), "hello")
      sha = resource.snapshot!
      expect(sha).to match(/\A[0-9a-f]{40}\z/)
    end

    it "returns HEAD when nothing changed" do
      sha1 = resource.snapshot!
      sha2 = resource.snapshot!
      expect(sha1).to eq(sha2)
    end

    it "captures new files" do
      sha1 = resource.snapshot!
      File.write(File.join(tmpdir, "new.txt"), "content")
      sha2 = resource.snapshot!
      expect(sha1).not_to eq(sha2)
    end

    it "captures file modifications" do
      File.write(File.join(tmpdir, "file.txt"), "v1")
      sha1 = resource.snapshot!
      File.write(File.join(tmpdir, "file.txt"), "v2")
      sha2 = resource.snapshot!
      expect(sha1).not_to eq(sha2)
    end

    it "captures file deletions" do
      path = File.join(tmpdir, "delete_me.txt")
      File.write(path, "bye")
      sha1 = resource.snapshot!
      File.delete(path)
      sha2 = resource.snapshot!
      expect(sha1).not_to eq(sha2)
    end
  end

  describe "#rollback!" do
    it "restores files to a previous state" do
      File.write(File.join(tmpdir, "file.txt"), "original")
      sha = resource.snapshot!

      File.write(File.join(tmpdir, "file.txt"), "modified")
      resource.snapshot!

      resource.rollback!(sha)
      expect(File.read(File.join(tmpdir, "file.txt"))).to eq("original")
    end

    it "removes files that didn't exist at snapshot time" do
      sha = resource.snapshot!

      new_file = File.join(tmpdir, "extra.txt")
      File.write(new_file, "extra")
      resource.snapshot!

      resource.rollback!(sha)
      expect(File.exist?(new_file)).to be false
    end

    it "restores deleted files" do
      path = File.join(tmpdir, "restore_me.txt")
      File.write(path, "important")
      sha = resource.snapshot!

      File.delete(path)
      resource.snapshot!

      resource.rollback!(sha)
      expect(File.read(path)).to eq("important")
    end
  end

  describe "#diff" do
    it "shows file changes between two snapshots" do
      sha1 = resource.snapshot!
      File.write(File.join(tmpdir, "added.txt"), "new content")
      sha2 = resource.snapshot!

      result = resource.diff(sha1, sha2)
      expect(result).to include("added.txt")
    end

    it "returns no changes for identical snapshots" do
      File.write(File.join(tmpdir, "stable.txt"), "same")
      sha = resource.snapshot!

      expect(resource.diff(sha, sha)).to eq("(no changes)")
    end
  end

  describe "#to_md" do
    it "shows recent git log" do
      File.write(File.join(tmpdir, "a.txt"), "a")
      resource.snapshot!

      md = resource.to_md
      expect(md).to include("snapshot")
    end

    it "shows init commit for empty repo" do
      expect(resource.to_md).to include("init")
    end
  end
end
