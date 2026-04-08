# Rename `chains add <alias> config <path>` to `chains add <alias> init <path>`

## Goal

Rename the `config` subcommand of `chains add` to `init` (mirrors
`git init`). Sibling `clone` is unchanged. The `.freechains/config.lua`
file inside chain trees is unchanged.

## Files

### Source

- `src/freechains.lua` lines 68-69
- `src/freechains/chains.lua` line 41

### Tests

- tst/cli-chains.lua, cli-reps.lua, cli-time.lua, cli-sign.lua,
  cli-begs.lua, cli-like.lua, cli-post.lua, cli-now.lua, cli-sync.lua,
  err-like.lua, err-post.lua, repl-local-head.lua, repl-local-begs.lua,
  repl-remote-head.lua, repl-remote-begs.lua

### Docs

- .claude/plans/all.md line 48
- .claude/plans/commands.md line 6
- .claude/plans/chains.md line 17

## Progress

- [x] src/freechains.lua
- [x] src/freechains/chains.lua
- [x] tests
- [x] design docs
