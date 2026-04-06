# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "mana_var_readwrite",
    layer: :mana,
    setup: -> {
      { x: 10, y: 20 }
    },
    prompt: "Set the variable `x` to 42 and `y` to the current value of `x` plus 8.",
    expect: ->(b) {
      b.local_variable_get(:x) == 42 && b.local_variable_get(:y) == 50
    },
    max_rounds: 3,
    max_tokens: 2000,
    ideal_path: %w[read_var write_var read_var write_var]
  )
)
