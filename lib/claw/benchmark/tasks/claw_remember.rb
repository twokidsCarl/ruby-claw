# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "claw_remember",
    layer: :claw,
    setup: -> {
      { important_fact: "The project deadline is March 15th" }
    },
    prompt: "Read the `important_fact` variable and remember it using the remember tool.",
    expect: ->(b) {
      memory = Claw.memory
      return false unless memory
      memory.long_term.any? { |m| m[:content].include?("March 15th") }
    },
    max_rounds: 3,
    max_tokens: 2000,
    ideal_path: %w[read_var remember]
  )
)
