# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::TUI::CommandProcessor do
  let(:test_binding) { Object.new.instance_eval { x = 42; binding } }
  let(:model) { Claw::TUI::Model.new(test_binding) }

  before { model.init }

  describe ".dispatch" do
    it "handles /help via process_help" do
      m, _cmd = described_class.dispatch(model, "/help")
      expect(m).to be(model)
      help_msg = model.chat_history.find { |msg| msg[:role] == :system && msg[:content]&.include?("/snapshot") }
      expect(help_msg).not_to be_nil
      expect(help_msg[:content]).to include("/help")
    end

    it "handles /new via process_new" do
      model.chat_history << { role: :user, content: "stale" }
      described_class.dispatch(model, "/new")
      expect(model.chat_history.size).to eq(1) # only the "New session." marker
      expect(model.chat_history.first[:content]).to include("New session")
    end

    it "handles /plan via process_plan (toggle)" do
      expect(model.mode).to eq(:normal)
      described_class.dispatch(model, "/plan")
      expect(model.mode).to eq(:plan)
      described_class.dispatch(model, "/plan")
      expect(model.mode).to eq(:normal)
    end

    it "delegates unknown commands to Claw::Commands" do
      # /status is a real Claw::Commands command — should produce some
      # system message via the command_result path
      before_count = model.chat_history.size
      described_class.dispatch(model, "/status")
      expect(model.chat_history.size).to be > before_count
    end

    it "returns [model, command] tuple in all cases" do
      result = described_class.dispatch(model, "/help")
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result[0]).to be(model)
    end
  end

  describe "/help content" do
    it "lists all major slash commands" do
      described_class.dispatch(model, "/help")
      help_content = model.chat_history.last[:content]
      %w[/help /new /status /snapshot /rollback /diff /history /plan].each do |cmd|
        expect(help_content).to include(cmd)
      end
    end
  end
end
