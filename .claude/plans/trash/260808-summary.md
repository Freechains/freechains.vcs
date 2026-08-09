# Trash index (260808)

Plan versions rescued from branches before their removal.
Kept only the largest version per name; equal or strictly
smaller versions were dropped (assumed subsumed). Prefix =
source branch.

# Files

- `b803-260802-redesign.md` (961 lines, branch
  260803-redesign, tip 08-07) — the full redesign: Lua DB as
  action layer, join commits, `actions/<id>.lua`, payload
  eviction, ID = blob hash; NEWEST version, adds the S-step
  ladder, S15 state snapshots (`.git/states/`), S16
  peak-over-backs. Dropped: 595-line base (b802/b807/main) and
  728-line intermediate (b806)
- `b807-260807-redesign.md` (branch 260807-redesign, tip
  08-08) — local state snapshots design: remote state ignored,
  parent-anchored backfill walk, one-step phase 1,
  bug-forged-state expectations flip to "forgery inert".
  ACTIVE line of work; restore to `.claude/plans/` to continue.
  Dropped: older main-worktree snapshot
- `b802-state-hash.md` (branch 260802-bug-forged-state) —
  live `state-hash.md` + cross-links naming the non-FF hole;
  superset of the live copy

# Dropped (nothing else lost)

- `260803-forged-state.md` branch variants: smaller than the
  live copy in `.claude/plans/`
- `260802-state-verify.md`, `260802-remove-blob.md`: still
  live in `.claude/plans/`
- branch test files: see `tst/trash/260808-summary.md`
