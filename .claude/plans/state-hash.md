# Plan: state-hash (FF integrity without cyclic garbage)

## Problem

On FF recv/send, remote's state files land verbatim on
disk. If remote is dishonest, B's query sees a lie.

If we naively recompute + overwrite + commit on every FF,
sync without new data creates endless state commits
(cyclic garbage).

## Goal

Verify remote state without unconditional rewrite.

## Approach: tree-hash compare

Git already stores `.freechains/state/` as a subtree.
Compute hash of computed state equivalently, compare to
remote's tree hash.

    git rev-parse FETCH_HEAD:.freechains/state
    # vs computed G_rem serialized identically

## Options

### A. Pure git compare (preferred)

1. Phase 1 replay builds G_rem.
2. Write G_rem to `tmp/state/` + `git hash-object`
   each file.
3. Combine into a tree hash, compare to
   `FETCH_HEAD:.freechains/state`.
4. If equal -> accept FF as-is (no new commit).
5. If differ -> reset past remote state tip + write
   G_rem + new state commit.

### B. Embedded `state-hash` trailer

Each state commit carries:

    Freechains: state
    Freechains-state-hash: <sha256 of sorted serial>

FF compare: trailer of remote's state tip vs sha256 of
local G_rem.serial(). No git tree walking.

### C. File-content compare

Read each `.lua` file as string, compare to
`serial(G_rem.*)`. Simple, no hashing, no git plumbing.

## Idempotency

All three options converge to: write only when differ.
No new commits when state matches -> no cyclic garbage.

## Recommendation

**A selected.** Reuse git's native tree hash: hash
serialized G_rem blobs via `git hash-object` and compare
to `git ls-tree FETCH_HEAD:.freechains/state`.

**C** (file byte compare) retained as fallback for the
non-FF case (no committed tree to compare against yet).

**B** avoids reading files but introduces a new trailer
and a hash algorithm dependency; skip.

## Name: `state-hash`

If/when option B lands, trailer is:

    Freechains-state-hash: <hash>

## Scope

- recv FF: currently trusts remote -> add compare
- recv non-FF: already writes G_fst; make write
  conditional on differ

(send hook dropped from scope)

## TODO

- [x] recv FF: compare G_rem tree-hash vs FETCH_HEAD;
  skip commit on match
- [x] recv FF: on differ, reset past state tip + write +
  commit
- [x] recv non-FF: make write conditional (disk byte
  compare)
