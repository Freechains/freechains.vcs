# Plan: Create `src/constants.lua`

## Context

Hardcoded magic numbers are scattered across
`src/freechains` and documented in
`.claude/plans/hardcoded.md`.
Extract them into `src/constants.lua` returning a table,
require as `local C = require "constants"`, and replace
all occurrences. Then delete `hardcoded.md`.

## Critical Files

| File                         | Action | Purpose                     |
|------------------------------|--------|-----------------------------|
| `src/constants.lua`          | new    | All constants with comments |
| `src/freechains`             | edit   | Require + use `C.XXX`      |
| `.claude/plans/hardcoded.md` | delete | Superseded by constants.lua |

## Steps

- [x] Step 1: Create `src/constants.lua`
- [x] Step 2: Edit `src/freechains`
- [x] Step 3: Delete `.claude/plans/hardcoded.md`
- [x] Verification: run tests
