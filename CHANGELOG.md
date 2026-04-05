# Changelog

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
