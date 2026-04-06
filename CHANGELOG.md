# Changelog

## [0.2.0] - 2026-04-06

### Added
- **Three-layer tool system** (V9): core (always loaded), project (on-demand), hub (remote)
  - `Claw::Tool` mixin with declarative DSL: `tool_name`, `description`, `parameter`
  - `Claw::ToolIndex` — regex-based file scanning of `.ruby-claw/tools/*.rb` without require
  - `Claw::ToolRegistry` — manages tool lifecycle: search, load, unload, register with Mana
  - `search_tools` and `load_tool` agent-facing Mana tools for dynamic discovery
- `Claw::Forge` — `/forge <method_name>` promotes eval-defined methods to formal tool classes
- `Claw::AutoForge` — detects repeated eval patterns in traces, suggests tool promotion
- `Claw::Hub` — HTTP client for community tool hub (search + download)
- **Web Console** (V10): local Sinatra-based observability UI at localhost:4567
  - `Claw::Console::Server` — Sinatra app with 8 page routes + full REST API
  - `Claw::Console::EventLogger` — structured JSONL append-only event log with Mutex
  - `Claw::Console::SSE` — Server-Sent Events streaming for real-time monitoring
  - Pages: Dashboard, Prompt Inspector, LLM Monitor, Trace Explorer, Memory, Tools, Snapshots, Experiments
  - API endpoints: GET/POST for status, events, traces, memory, prompt, tools, snapshots
- `claw console [--port N]` CLI subcommand
- Proactive `remember` tool guidance in system prompt

### Fixed
- Path traversal vulnerability in `/api/traces/:id` — now validates IDs
- Hub download path sanitization — prevents directory traversal via tool names
- Console POST endpoints now validate JSON and required fields
- CLI `--port` parsing handles missing argument
- `Forge` filename sanitization handles uppercase method names
- `Claw.reset!` now clears `Tool.tool_classes` to prevent test leaks

## [0.1.8] - 2026-04-05

### Added
- `Claw::ChildRuntime` — multi-agent parent-child architecture with isolated threads
- `Claw::Resources::WorktreeResource` — git worktree isolation for child agents
- `Runtime#fork_async` spawns child agents with deep-copied variables and optional role/model override
- Child lifecycle: `start!` / `join` / `cancel!` / `diff` / `merge!` with Mutex-based thread safety
- Resource `merge_from!` interface for merging child changes back to parent

## [0.1.7] - 2026-04-05

### Added
- `Claw::Benchmark` framework — automated task-based evaluation of agent capabilities
- 9 built-in benchmark tasks across mana, claw, runtime, and evolution layers
- `Claw::Benchmark::Scorer` — scoring formula: correctness, rounds, tokens, tool path (Levenshtein)
- `Claw::Benchmark::Report` — Markdown report generation with per-task and per-layer breakdown
- `Claw::Benchmark::Diff` — compare two benchmark reports
- `Claw::Benchmark::Trigger` — auto-triggers evolution on score regression or 3 consecutive failures
- CLI: `claw benchmark run`, `claw benchmark diff <a> <b>`

## [0.1.6] - 2026-04-05

### Added
- Full-screen TUI built on Charm Ruby (bubbletea, lipgloss, bubbles, glamour)
- MVU architecture: Model/Update/View with 4-zone layout (status bar, chat panel, status panel, command bar)
- `Claw::PlanMode` — two-phase plan-then-execute workflow with fork safety
- `Claw::Roles` — agent identity management via `.ruby-claw/roles/*.md`
- `Claw::Commands` — extracted pure-function slash command module
- `Claw::CLI` — headless CLI for non-interactive subcommands
- TUI modules: syntax highlighting, tab completion, object explorer, file cards, text folding
- CLI subcommands: `claw status`, `claw history`, `claw rollback`, `claw trace`, `claw evolve`, `claw benchmark`

### Changed
- Default `claw` entry point now launches TUI instead of legacy REPL
- `Chat.start` delegates to `TUI.start` for backward compatibility
- `claw init` now creates `roles/` directory with default role

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
