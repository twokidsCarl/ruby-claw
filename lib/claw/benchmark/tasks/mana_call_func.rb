# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "mana_call_func",
    layer: :mana,
    setup: -> {
      {
        greet: ->(name) { "Hello, #{name}!" },
        result: nil
      }
    },
    prompt: "Call the `greet` function with the argument \"World\" and store the return value in `result`.",
    expect: ->(b) {
      b.local_variable_get(:result) == "Hello, World!"
    },
    max_rounds: 3,
    max_tokens: 2000,
    ideal_path: %w[read_var call_function write_var]
  )
)
