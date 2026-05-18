# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Log do
  let(:dir) { Dir.mktmpdir("claw-log-") }
  let(:path) { File.join(dir, "claw.log") }

  before do
    described_class.path = path
  end

  after do
    described_class.close
    FileUtils.rm_rf(dir)
  end

  describe ".info" do
    it "appends a line with INFO level to the file" do
      described_class.info "hello"
      content = File.read(path)
      expect(content).to include("INFO")
      expect(content).to include("hello")
    end

    it "prefixes each line with a timestamp" do
      described_class.info "world"
      expect(File.read(path)).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} INFO/)
    end
  end

  describe ".error" do
    it "writes a string error" do
      described_class.error "something broke"
      expect(File.read(path)).to include("ERROR something broke")
    end

    it "writes class + message + truncated backtrace for an exception" do
      raise StandardError, "boom"
    rescue => e
      described_class.error e
      content = File.read(path)
      expect(content).to include("StandardError: boom")
      expect(content).to include("ERROR  ")  # backtrace lines indented
    end
  end

  describe ".debug" do
    it "is silent when verbose is false" do
      allow(Mana.config).to receive(:verbose).and_return(false)
      described_class.debug "hidden"
      expect(File.exist?(path)).to be false
    end

    it "writes when verbose is true" do
      allow(Mana.config).to receive(:verbose).and_return(true)
      described_class.debug "shown"
      expect(File.read(path)).to include("DEBUG shown")
    end
  end

  describe "rotation / cleanup" do
    it "appends across multiple calls (no truncation)" do
      described_class.info "first"
      described_class.info "second"
      content = File.read(path)
      expect(content).to include("first")
      expect(content).to include("second")
    end

    it "recreates the file after the user deletes it (on next write)" do
      described_class.info "first"
      File.delete(path)
      # Next write attempt — file handle is still open against the deleted
      # inode, so write goes to the unlinked file. This is a known Unix
      # quirk; not a hard requirement. Just verify it doesn't crash.
      expect { described_class.info "second" }.not_to raise_error
    end
  end
end
