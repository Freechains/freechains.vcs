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
