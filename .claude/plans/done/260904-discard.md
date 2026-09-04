# Rename `discard` -> `discard`

- shorter, matches git/hg vocabulary for dropping local work
- `discard` wrongly suggests leaving the chain
- `discard` fits parked begs naturally

# Scope

- `git mv` files
    - `src/freechains/chain/discard.lua` -> `discard.lua`
    - `tst/cli-discard.lua` -> `cli-discard.lua`
    - `tst/discard-strange.lua` -> `discard-strange.lua`
- source: `freechains.lua`, `chain/init.lua`, `action.lua`,
  `get.lua`, `sweep.lua`
    - CLI command, `ARGS.discard`, error strings, comments
- tests: `cli-sweep.lua`, `dag.lua`, `cli-revoke.lua`
- build: `Makefile`, `freechains-0.21-1.rockspec`
    - new `freechains-dev-3.rockspec` (dev-2 moved to `old/`)
- docs: `doc/cli.md`, `doc/guide.md`, `guide.sh`, `README.md`
- plans: `commands.md`, `threats.md`, `260819-blacklist.md`,
  `260829-otim.md`, `260903-128KB.md`
- `HISTORY.md`: note the rename

# Won't do

- rewrite `.claude/plans/done/*` (historical)
- git history / old release notes

# Progress

- [x] plan written
- [x] files moved
- [x] source + tests replaced
- [x] build + docs + plans replaced
- [x] tests run (26/09/04: all pass)
