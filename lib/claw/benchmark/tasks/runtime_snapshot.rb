# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "runtime_snapshot",
    layer: :runtime,
    setup: -> {
      { data: "original" }
    },
    prompt: "Read `data`, then change `data` to \"modified\". The runtime will track the change.",
    expect: ->(b) {
      b.local_variable_get(:data) == "modified"
    },
    max_rounds: 3,
    max_tokens: 2000,
    ideal_path: %w[read_var write_var]
  )
)
