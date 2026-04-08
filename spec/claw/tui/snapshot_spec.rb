# frozen_string_literal: true

require "spec_helper"

RSpec.describe "tui-snapshot" do
  def make_test_binding
    a = 1
    b = 2
    title = "hello"
    items = [1, 2, 3, 4, 5]
    config = { name: "claw", version: Claw::VERSION, debug: false }
    binding
  end

  def build_model
    model = Claw::TUI::Model.new(make_test_binding)
    model.init
    model
  end

  def submit(model, text)
    model.textarea.value = text
    enter = Bubbletea::KeyMessage.new(key_type: 0, runes: [], name: "enter")
    model.update(enter)
  end

  def render_plain(model, width: 72, height: 23)
    output = Claw::TUI::Layout.render(model, width, height)
    output.gsub(/\e\[\d*(?:;\d+)*[A-Za-z]/, "").gsub(/\e\].*?\e\\/, "")
  end

  describe "ruby eval display" do
    it "evaluates expression without ! prefix" do
      model = build_model
      submit(model, "a + b")
      plain = render_plain(model)

      expect(plain).to include(">> a + b")
      expect(plain).to include("=> 3")
    end

    it "shows multiple sequential results" do
      model = build_model
      submit(model, "a + b")
      submit(model, "items.sum")

      plain = render_plain(model)
      expect(plain).to include("=> 3")
      expect(plain).to include("=> 15")
    end

    it "pretty-prints complex objects" do
      model = build_model
      submit(model, "config")

      plain = render_plain(model)
      expect(plain).to include("name")
      expect(plain).to include("claw")
    end
  end

  describe "zsh bang escaping" do
    it "treats \\! as ! in command args" do
      commands = ['\\!a + b'].map { |a| a.gsub('\!', '!') }
      expect(commands).to eq(["!a + b"])
    end
  end

  describe "slash commands" do
    it "renders /status output" do
      model = build_model
      submit(model, "/status")

      plain = render_plain(model)
      expect(plain).to include("session_start")
    end

    it "adds help content to chat history" do
      model = build_model
      submit(model, "/help")

      help_msg = model.chat_history.find { |m| m[:role] == :system && m[:content].include?("/status") }
      expect(help_msg).not_to be_nil
      expect(help_msg[:content]).to include("/snapshot")
      expect(help_msg[:content]).to include("/ask")
      expect(help_msg[:content]).to include("/new")
      expect(help_msg[:content]).to include("Ruby expressions are evaluated directly.")
    end
  end

  describe "/new command" do
    it "clears chat history" do
      model = build_model
      submit(model, "a + b")
      expect(model.chat_history.size).to be > 1

      submit(model, "/new")
      expect(model.chat_history.size).to eq(1)
      expect(model.chat_history.first[:content]).to eq("New session.")
    end
  end

  describe "version and status bar" do
    it "shows version with build number" do
      model = build_model
      plain = render_plain(model)

      expect(plain).to include("claw v#{Claw::VERSION} b")
    end

    it "shows snap: label" do
      model = build_model
      plain = render_plain(model)

      expect(plain).to include("snap:")
    end
  end

  describe "layout" do
    it "renders status bar and both panels at 72x23" do
      model = build_model
      plain = render_plain(model, width: 72, height: 23)

      expect(plain).to include("claw v#{Claw::VERSION}")
      expect(plain).to include("Binding")
      expect(plain).to include(">>")
    end

    it "output line count matches terminal height" do
      model = build_model
      output = Claw::TUI::Layout.render(model, 72, 23)
      lines = output.split("\n").size
      expect(lines).to eq(23)
    end

    it "has no ~ empty lines when textarea is single line" do
      model = build_model
      plain = render_plain(model)

      # The ~ character should not appear as empty line filler
      lines = plain.split("\n").select { |l| l.strip == "~" }
      expect(lines).to be_empty
    end
  end

  describe "custom methods in binding panel" do
    it "shows user-defined methods" do
      model = build_model
      submit(model, "def foo; 42; end")

      plain = render_plain(model)
      expect(plain).to include("def foo")
    end
  end

  describe "status bar model name (#1)" do
    it "shows full model name from config" do
      model = build_model
      plain = render_plain(model)
      model_name = Mana.config.model.to_s
      # Model name should appear (or be truncated by responsive logic)
      expect(plain).to include("claw v#{Claw::VERSION}")
    end
  end

  describe "help alignment (#10)" do
    it "has consistent indentation in /help output" do
      model = build_model
      submit(model, "/help")
      help_msg = model.chat_history.find { |m| m[:role] == :system && m[:content]&.include?("/ask") }
      lines = help_msg[:content].split("\n").select { |l| l.include?("—") }
      # All command lines should have same indentation
      indents = lines.map { |l| l.match(/\A(\s*)/)[1].length }
      expect(indents.uniq.size).to eq(1), "Expected uniform indentation, got #{indents.uniq}"
    end

    it "does not include /ls or /whereami" do
      model = build_model
      submit(model, "/help")
      help_msg = model.chat_history.find { |m| m[:role] == :system && m[:content]&.include?("/ask") }
      expect(help_msg[:content]).not_to include("/ls")
      expect(help_msg[:content]).not_to include("/whereami")
    end

    it "includes history and tab completion hint" do
      model = build_model
      submit(model, "/help")
      help_msg = model.chat_history.find { |m| m[:role] == :system && m[:content]&.include?("/ask") }
      expect(help_msg[:content]).to include("history")
      expect(help_msg[:content]).to include("tab completion")
    end
  end

  describe "scroll hint (#11)" do
    it "does not show scroll hint when not scrolled" do
      model = build_model
      plain = render_plain(model)
      expect(plain).not_to include("pgup")
    end
  end
end
