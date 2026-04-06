# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Roles do
  let(:claw_dir) { Dir.mktmpdir("claw-roles-") }

  before do
    roles_dir = File.join(claw_dir, "roles")
    FileUtils.mkdir_p(roles_dir)
    File.write(File.join(roles_dir, "debugger.md"), "You are a debugging expert.")
    File.write(File.join(roles_dir, "reviewer.md"), "You are a code reviewer.")
  end

  after do
    FileUtils.rm_rf(claw_dir)
    Claw::Roles.clear!
  end

  describe ".list" do
    it "returns available role names" do
      roles = Claw::Roles.list(claw_dir)
      expect(roles).to contain_exactly("debugger", "reviewer")
    end

    it "returns empty array when no roles directory" do
      expect(Claw::Roles.list("/nonexistent")).to eq([])
    end
  end

  describe ".load" do
    it "loads role content as a string" do
      content = Claw::Roles.load("debugger", claw_dir)
      expect(content).to eq("You are a debugging expert.")
    end

    it "raises for missing role" do
      expect { Claw::Roles.load("nonexistent", claw_dir) }
        .to raise_error(RuntimeError, /Role not found/)
    end
  end

  describe ".switch!" do
    it "sets current role" do
      Claw::Roles.switch!("debugger", claw_dir)
      current = Claw::Roles.current
      expect(current).not_to be_nil
      expect(current[:name]).to eq("debugger")
    end
  end

  describe ".current" do
    it "returns nil when no role set" do
      expect(Claw::Roles.current).to be_nil
    end
  end

  describe ".clear!" do
    it "clears the current role" do
      Claw::Roles.switch!("debugger", claw_dir)
      Claw::Roles.clear!
      expect(Claw::Roles.current).to be_nil
    end
  end
end
