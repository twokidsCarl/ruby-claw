# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::FileCard do
  describe ".extract_refs" do
    it "extracts @filename references" do
      refs = described_class.extract_refs("check @user.rb and @config.yml")
      expect(refs).to eq(["user.rb", "config.yml"])
    end

    it "extracts glob patterns" do
      refs = described_class.extract_refs("look at @*.rb")
      expect(refs).to eq(["*.rb"])
    end

    it "extracts paths with directories" do
      refs = described_class.extract_refs("read @lib/claw/version.rb")
      expect(refs).to eq(["lib/claw/version.rb"])
    end

    it "returns empty for no refs" do
      refs = described_class.extract_refs("no file refs here")
      expect(refs).to be_empty
    end
  end

  describe ".resolve" do
    it "resolves existing file" do
      paths = described_class.resolve("Gemfile")
      expect(paths).to eq(["Gemfile"])
    end

    it "returns empty for nonexistent file" do
      paths = described_class.resolve("no_such_file_xyz.rb")
      expect(paths).to be_empty
    end

    it "resolves glob patterns" do
      paths = described_class.resolve("lib/claw/version.rb")
      expect(paths).to eq(["lib/claw/version.rb"])
    end
  end

  describe ".render_card" do
    it "renders a file card for existing file" do
      card = described_class.render_card("lib/claw/version.rb")
      expect(card).to include("version.rb")
      expect(card).to include("Ruby")
    end

    it "shows not found for missing file" do
      card = described_class.render_card("no_such_file.rb")
      expect(card).to include("not found")
    end
  end

  describe ".read_for_context" do
    it "reads file content with header" do
      content = described_class.read_for_context("lib/claw/version.rb")
      expect(content).to include("# File: lib/claw/version.rb")
      expect(content).to include("VERSION")
    end

    it "returns empty for missing file" do
      content = described_class.read_for_context("no_such_file.rb")
      expect(content).to eq("")
    end
  end
end
