# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "runtime_fork",
    layer: :runtime,
    setup: -> {
      { value: 100, doubled: nil }
    },
    prompt: "Read `value`, compute its double, and store the result in `doubled`.",
    expect: ->(b) {
      b.local_variable_get(:doubled) == 200
    },
    max_rounds: 3,
    max_tokens: 2000,
    ideal_path: %w[read_var eval_code write_var]
  )
)
