# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "mana_eval",
    layer: :mana,
    setup: -> {
      { numbers: [3, 7, 2, 9, 1] }
    },
    prompt: "Sort the `numbers` array in descending order and store the result back in `numbers`.",
    expect: ->(b) {
      b.local_variable_get(:numbers) == [9, 7, 3, 2, 1]
    },
    max_rounds: 3,
    max_tokens: 2000,
    ideal_path: %w[read_var eval_code]
  )
)
