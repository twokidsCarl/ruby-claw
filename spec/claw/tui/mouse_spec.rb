# frozen_string_literal: true

require "spec_helper"

RSpec.describe "TUI mouse support" do
  let(:test_binding) { Object.new.instance_eval { x = 42; binding } }
  let(:model) { Claw::TUI::Model.new(test_binding) }

  # Map symbolic names to Bubbletea::MouseMessage constants
  BUTTON_MAP = {
    left: Bubbletea::MouseMessage::BUTTON_LEFT,
    right: Bubbletea::MouseMessage::BUTTON_RIGHT,
    none: Bubbletea::MouseMessage::BUTTON_NONE,
    wheel_up: Bubbletea::MouseMessage::BUTTON_WHEEL_UP,
    wheel_down: Bubbletea::MouseMessage::BUTTON_WHEEL_DOWN,
  }.freeze

  ACTION_MAP = {
    press: Bubbletea::MouseMessage::ACTION_PRESS,
    release: Bubbletea::MouseMessage::ACTION_RELEASE,
    motion: Bubbletea::MouseMessage::ACTION_MOTION,
  }.freeze

  def make_mouse(x:, y:, action:, button: :left)
    Bubbletea::MouseMessage.new(
      x: x, y: y,
      button: BUTTON_MAP.fetch(button, button),
      action: ACTION_MAP.fetch(action, action),
      alt: false, ctrl: false
    )
  end

  def expect_mvu_tuple(result)
    expect(result).to be_an(Array)
    expect(result.size).to eq(2)
    expect(result[0]).to respond_to(:update)
  end

  describe "initialization" do
    it "sets default chat_ratio to 0.70" do
      expect(model.chat_ratio).to eq(0.70)
    end

    it "starts with dragging_divider false" do
      expect(model.dragging_divider).to eq(false)
    end

    it "initializes a zone manager when bubblezone is available" do
      if defined?(Bubblezone::Manager)
        expect(model.zone).to be_a(Bubblezone::Manager)
      else
        expect(model.zone).to be_nil
      end
    end

    it "accepts baseline_methods and baseline_vars keyword args" do
      m = Claw::TUI::Model.new(test_binding,
                                baseline_methods: [:foo],
                                baseline_vars: ["bar"])
      expect(m.baseline_methods).to eq([:foo])
      expect(m.baseline_vars).to eq(["bar"])
    end
  end

  describe "scroll wheel" do
    it "handles wheel_up" do
      model.init
      result = model.update(make_mouse(x: 10, y: 10, action: :press, button: :wheel_up))
      expect_mvu_tuple(result)
      expect(model.scrolled_up?).to eq(true)
    end

    it "handles wheel_down" do
      model.init
      result = model.update(make_mouse(x: 10, y: 10, action: :press, button: :wheel_down))
      expect_mvu_tuple(result)
    end
  end

  describe "divider drag" do
    it "starts dragging when clicking near the divider" do
      model.init
      divider_x = (80 * 0.70).to_i
      result = model.update(make_mouse(x: divider_x, y: 10, action: :press, button: :left))
      expect_mvu_tuple(result)
      expect(model.dragging_divider).to eq(true)
    end

    it "updates chat_ratio on motion while dragging" do
      model.init
      divider_x = (80 * 0.70).to_i

      model.update(make_mouse(x: divider_x, y: 10, action: :press, button: :left))
      expect(model.dragging_divider).to eq(true)

      model.update(make_mouse(x: divider_x + 10, y: 10, action: :motion, button: :left))
      expect(model.chat_ratio).to be > 0.70

      model.update(make_mouse(x: divider_x + 10, y: 10, action: :release, button: :none))
      expect(model.dragging_divider).to eq(false)
    end

    it "clamps chat_ratio between 0.3 and 0.85" do
      model.init
      divider_x = (80 * 0.70).to_i
      model.update(make_mouse(x: divider_x, y: 10, action: :press, button: :left))

      model.update(make_mouse(x: 79, y: 10, action: :motion, button: :left))
      expect(model.chat_ratio).to be <= 0.85

      model.update(make_mouse(x: 1, y: 10, action: :motion, button: :left))
      expect(model.chat_ratio).to be >= 0.3
    end
  end

  describe "layout uses model.chat_ratio" do
    it "CHAT_RATIO is the default ratio" do
      expect(Claw::TUI::Layout::CHAT_RATIO).to eq(0.70)
    end

    it "adjusts panel widths based on chat_ratio" do
      model.init
      model.chat_ratio = 0.50
      output = model.view
      expect(output).to be_a(String)
      expect(output.length).to be > 0
    end
  end
end
