# ruby-claw

Agent framework for Ruby, built on [ruby-mana](https://github.com/twokidsCarl/ruby-mana).

Claw extends mana's LLM engine with interactive chat, persistent memory with compaction, session persistence, and runtime state serialization.

## Install

```ruby
gem "ruby-claw"
```

## Usage

```ruby
require "claw"

# Start interactive chat
Claw.chat

# Access enhanced memory
Claw.memory.search("ruby")
Claw.memory.save_session

# Configure
Claw.configure do |c|
  c.memory_pressure = 0.7
  c.persist_session = true
end
```

## Components

- **Claw::Chat** — interactive REPL with streaming markdown output
- **Claw::Memory** — compaction, search, and session persistence on top of Mana::Memory
- **Claw::Serializer** — save/restore runtime variables and method definitions
- **Claw::Knowledge** — extended knowledge base with agent-specific topics

## License

MIT
