# frozen_string_literal: true

Claw::Benchmark::Tasks.register(
  Claw::Benchmark::Task.new(
    id: "mana_knowledge",
    layer: :mana,
    setup: -> {
      { answer: nil }
    },
    prompt: "Use knowledge lookup to find what the Array#flatten method does, then set `answer` to the string \"recursive flatten\".",
    expect: ->(b) {
      val = b.local_variable_get(:answer)
      val.is_a?(String) && val.downcase.include?("flatten")
    },
    max_rounds: 4,
    max_tokens: 3000,
    ideal_path: %w[knowledge_lookup write_var]
  )
)
