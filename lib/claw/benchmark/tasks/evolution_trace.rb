# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "evolution_trace",
    layer: :evolution,
    setup: -> {
      { items: [1, 2, 3], total: nil }
    },
    prompt: "Calculate the sum of all elements in `items` and store it in `total`.",
    expect: ->(b) {
      b.local_variable_get(:total) == 6
    },
    max_rounds: 3,
    max_tokens: 2000,
    ideal_path: %w[read_var eval_code write_var]
  )
)
