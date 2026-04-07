# CLAUDE.md — Rules for working on ruby-claw

## Build number

Every time you change code, increment the BUILD constant in `lib/claw/version.rb`.

Format: `YYYYMMDD-NNN` where NNN is a sequential number starting at 001 each day.

Example: `20260407-001` → `20260407-002` → `20260407-003`

## Git workflow

Never push directly to main. Always: branch → PR → CI → review → merge.

## Testing

Run `bundle exec rspec spec/claw/tui/` after TUI changes.

Use `ruby exe/tui-snapshot 72 23 'a + b'` to verify rendered TUI output without a real terminal.

## Terminal constraints

The user's terminal is 72x23. All UI must fit at this size. Test with `exe/tui-snapshot 72 23`.
