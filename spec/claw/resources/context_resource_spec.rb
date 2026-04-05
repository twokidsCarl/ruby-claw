# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Resources::ContextResource do
  let(:context) { Mana::Context.new }
  let(:resource) { described_class.new(context) }

  describe "#snapshot!" do
    it "captures messages and summaries" do
      context.messages << { role: "user", content: "hello" }
      context.summaries << "greeting"

      token = resource.snapshot!
      expect(token[:messages].size).to eq(1)
      expect(token[:summaries]).to eq(["greeting"])
    end

    it "returns a deep copy (mutations don't affect snapshot)" do
      context.messages << { role: "user", content: "hello" }
      token = resource.snapshot!

      context.messages << { role: "assistant", content: "hi" }
      expect(token[:messages].size).to eq(1)
    end
  end

  describe "#rollback!" do
    it "restores messages and summaries" do
      context.messages << { role: "user", content: "hello" }
      token = resource.snapshot!

      context.messages << { role: "assistant", content: "hi" }
      context.messages << { role: "user", content: "bye" }
      context.summaries << "conversation summary"

      resource.rollback!(token)

      expect(context.messages.size).to eq(1)
      expect(context.messages.first[:content]).to eq("hello")
      expect(context.summaries).to be_empty
    end

    it "restores with deep copy (post-rollback mutations don't affect token)" do
      token = resource.snapshot!

      resource.rollback!(token)
      context.messages << { role: "user", content: "new" }

      # Original token should be unchanged for re-rollback
      resource.rollback!(token)
      expect(context.messages).to be_empty
    end
  end

  describe "#diff" do
    it "shows message count changes" do
      token_a = resource.snapshot!
      context.messages << { role: "user", content: "hello" }
      token_b = resource.snapshot!

      result = resource.diff(token_a, token_b)
      expect(result).to include("messages: 0 → 1")
      expect(result).to include("[user] hello")
    end

    it "returns no changes for identical snapshots" do
      context.messages << { role: "user", content: "hello" }
      token_a = resource.snapshot!
      token_b = resource.snapshot!

      expect(resource.diff(token_a, token_b)).to eq("(no changes)")
    end
  end

  describe "#to_md" do
    it "renders message and summary counts" do
      context.messages << { role: "user", content: "hi" }
      context.summaries << "sum"

      expect(resource.to_md).to eq("1 messages, 1 summaries")
    end
  end
end
