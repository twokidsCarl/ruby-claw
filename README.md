# ruby-claw 🦀

[![Gem Version](https://badge.fury.io/rb/ruby-claw.svg)](https://rubygems.org/gems/ruby-claw) · [GitHub](https://github.com/twokidsCarl/ruby-claw)

AI Agent framework for Ruby. Built on [ruby-mana](https://github.com/twokidsCarl/ruby-mana).

## What is Claw?

Claw turns ruby-mana's embedded LLM engine into a full agent with persistent memory, interactive chat, and session recovery. Think of it as the agent layer on top of mana's execution engine.

```ruby
gem install ruby-claw
```

## Features

### Interactive Chat REPL
```ruby
require "claw"
Claw.chat
```
Or from command line: `claw`

- Auto-detects Ruby code vs natural language
- Streaming output with markdown rendering
- `!` prefix forces Ruby eval
- Session persists across restarts

### Persistent Memory
Claw stores memories as human-readable Markdown in `.mana/`:

```
.mana/
  MEMORY.md       # Long-term facts (editable!)
  session.md      # Conversation summary
  values.json     # Variable snapshots
  definitions.rb  # Method definitions
  log/
    2026-03-29.md  # Daily interaction log
```

The LLM can `remember` facts that persist across sessions:
```ruby
claw> remember that the API uses OAuth2
claw> # ... next session ...
claw> what auth does our API use?
# => "OAuth2 — I remembered this from a previous session"
```

### Runtime Persistence
Variables and method definitions survive across sessions:
```ruby
claw> a = 42
claw> def greet(name) = "Hello #{name}"
claw> exit

$ claw  # restart
claw> a        # => 42
claw> greet("world")  # => "Hello world"
```

### Memory Compaction
When conversation grows large, old messages are automatically summarized in the background.

### Keyword Memory Search
With many memories (>20), only the most relevant are injected into prompts.

## Configuration

```ruby
Claw.configure do |c|
  c.memory_pressure = 0.7       # Compact when tokens > 70% of context window
  c.memory_keep_recent = 4      # Keep last 4 conversation rounds during compaction
  c.compact_model = nil          # nil = use main model for summarization
  c.persist_session = true       # Save/restore session across restarts
  c.memory_top_k = 10           # Max memories to inject when searching
  c.on_compact = ->(summary) { puts summary }
end

# Mana config (inherited)
Mana.configure do |c|
  c.model = "claude-sonnet-4-6"
  c.api_key = "sk-..."
end
```

## Relationship with ruby-mana

- **ruby-mana** = Embedded LLM engine (`~"..."` syntax, binding manipulation, tool calling)
- **ruby-claw** = Agent framework (chat REPL, memory, persistence, knowledge)

Claw depends on mana. You can use mana standalone for embedding LLM in Ruby code, or add claw for interactive agent features.

## License

MIT
