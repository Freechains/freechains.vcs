# Discard Across a Sync Merge

# Problem

- `discard <cid>` refuses any range holding a sync merge
    - "chain discard : unexpected merge"
- so a merged-in branch can never be dropped
- this blocks the refutation of 3.8.2 in the paper
    - a peer that already merged cannot rewind and dislike
    - its dislike descends from both branches and lands last
- verified: rewinding HEAD to the merge's first parent makes the
  whole sequence work, voiding the offending branch

# Goal

- let `discard` drop a whole merged-in sibling
- keep the current linear case untouched

# Design

- `--merge` allows the dropped range to hold sync merges
    - without it, keep the current error, plus a hint
- it composes with both forms
    - `discard --merge <cid>`: cid is on a merged-in sibling,
      land on `M^1`, the local tip before that merge M
    - `discard --keep --merge <cid>`: land on cid, which may sit
      before one or more merges
- find M by walking `rev-list --first-parent HEAD` for the oldest
  merge whose second-parent side contains cid
- the dropped range may hold merges
    - report only the actions, skip the merge commits
    - drop `refs/local/` and `refs/payloads/` for both

# Constraints

- never land before the merge base of the two branches
- keep the stale-beg cleanup as is

# Files

- src/freechains/chain/discard.lua
    - the tip search, the range filter, the header comment
- src/freechains/chain/init.lua
    - the `--merge` flag
- doc/guide.md and guide.sh
    - a discard-after-merge example

# Status (2026-10-03)

- DONE, final semantics (supersedes Design above)
    - one rule: discard drops the cid and everything BUILT ON it,
      nothing else; what survives must have a single tip
    - `--merge` required exactly when the drop cuts a sync merge
      (a dropped merge has a surviving parent); else
      "expected merge"; without it, "unexpected merge"
    - two surviving tips: "partial branch" (cid is not the first
      of its branch; only a new merge could keep both)
    - `--keep` and `--merge` are mutually exclusive (argparse):
      `--keep --merge` can never leave a single tip
    - a merge that goes WHOLE is a plain sequence: `--keep F`
      below the fork needs no flag
    - symmetric: `--merge a1` lands on b2, `--merge b1` on a2;
      no first-parent special case
- DONE src/freechains/chain/discard.lua: dropped set by
  `rev-list --parents --ancestry-path`, surviving parents, tip by
  `merge-base --independent`; drop loop skips merges in the report
- DONE src/freechains.lua: flags, mutex; doc/cli.md usage
- DONE tst/discard-strange.lua, diagrams per step
    - 1: `discard a1` and `--keep b2` refuse (was `--keep seed`,
      now a valid plain sequence)
    - 6: `--merge a2` partial, `--merge e1` expected merge,
      `--keep --merge` refused, `--merge a1` on A and on B
    - 7: full refutation (honest a1, fake a2, merge, discard,
      dislike, recv: a1 back, a2 voided, c1 reposted, B converges),
      then `--keep F` with no flag (A) and `--merge b1` (B)
- finding: a sync merge's first parent is the consensus winner,
  not the local line (sync.lua ln 211)
- finding: the precise cut at a2 is made by REPLAY, not discard
  (recv merges the last non-failing loser)
- won't do: re-merge of the kept part (the merge half of recv)
- won't do: error hint; "never land before the merge base"
- not done: guide example; guide.sh does not exist
- suites: discard-strange and cli-discard pass; full suite pending
