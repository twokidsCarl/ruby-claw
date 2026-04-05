# Changelog

## [0.1.5] - 2026-04-05

### Added
- `Claw::Evolution` — self-evolution loop: reads traces, LLM diagnosis, fork/apply/test/keep-or-rollback
- `/evolve` REPL command to trigger an evolution cycle
- Evolution logs written to `.ruby-claw/evolution/`

## [0.1.4] - 2026-04-05

### Added
- `Claw::Init` — `claw init` scaffolds a new project with editable gem source
- Clones ruby-claw and ruby-mana to `.ruby-claw/gems/`
- Generates Gemfile with `path:` references, `system_prompt.md`, empty `MEMORY.md`
- Initializes git repo in `.ruby-claw/` with initial commit
- CLI subcommands: `claw init`, `claw version`, `claw help`

## [0.1.3] - 2026-04-05

### Added
- `Claw::Trace` — writes per-task Markdown trace files to `.ruby-claw/traces/`
- Traces capture timing, token usage, and tool call details per LLM iteration
- Auto-writes traces after each chat execution

### Changed
- Serializer `encode_value` now uses `MarshalMd.dump` instead of `Marshal.dump`
- Backward compatibility: old `"marshal"` type entries still decoded via `Marshal.load`
- `BindingResource` and all resources use MarshalMd for deep copy
- Added `marshal-md` gem dependency

## [0.1.2] - 2026-04-04

### Changed
- `Claw::Memory` is now fully independent (no longer inherits from `Mana::Memory`)
- Conversation context uses `context.messages` (renamed from `short_term`)
- Uses `Thread.current[:claw_memory]` instead of `:mana_memory`
- Remember tool registered via `Mana.register_tool` interface (no longer built into mana)
- Long-term memories injected into prompt via `Mana.register_prompt_section`

### Added
- `Claw::Memory.incognito?` / `Claw::Memory.incognito(&block)` — claw-owned incognito mode
- `Claw.incognito(&block)` — convenience method
- `Thread.current[:claw_incognito]` for incognito state

### Removed
- Dependency on `Mana::Context.incognito?` (incognito now self-contained in claw)

## [0.1.1] - 2026-03-27

### Added
- Markdown-based memory architecture (MEMORY.md, session.md, daily logs)
- Complete README with usage examples
- GitHub Pages website

## [0.1.0] - 2026-03-27

### Added
- Initial release: Chat REPL, persistent memory, compaction, session persistence
- Knowledge provider, runtime serializer
- Built on ruby-mana provider interfaces
