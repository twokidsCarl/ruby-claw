# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Config do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "sets memory_pressure to 0.7" do
      expect(config.memory_pressure).to eq(0.7)
    end

    it "sets memory_keep_recent to 4" do
      expect(config.memory_keep_recent).to eq(4)
    end

    it "sets compact_model to nil" do
      expect(config.compact_model).to be_nil
    end

    it "sets on_compact to nil" do
      expect(config.on_compact).to be_nil
    end

    it "sets persist_session to true" do
      expect(config.persist_session).to be(true)
    end

    it "sets memory_top_k to 10" do
      expect(config.memory_top_k).to eq(10)
    end
  end

  describe "Claw.configure" do
    it "yields config for modification" do
      Claw.configure do |c|
        c.memory_pressure = 0.5
        c.memory_keep_recent = 2
      end

      expect(Claw.config.memory_pressure).to eq(0.5)
      expect(Claw.config.memory_keep_recent).to eq(2)
    end
  end
end
