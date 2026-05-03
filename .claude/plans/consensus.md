# Consensus: Fetch Validation Pipeline

## Git's Built-in Validation (fetch)

On `git fetch`, git validates automatically:

- **Object integrity** — SHA hash of every object matches
  content
- **Object graph** — commits reference valid parents, trees,
  blobs
- **Transfer protocol** — packfile checksums, no corruption

These guarantees are free — no freechains code needed.

## Consensus Rule

The side whose first divergent commit (immediately
after common ancestor) has the **earlier author date**
wins. Winner's branch is accepted as-is. Loser's
branch is validated commit-by-commit.

Both peers arrive at the same decision because the
dates are embedded in the commits.

## Validation (loser branch)

After fetch, the loser's commits are validated one by
one (oldest first) against the winner's state:

- **Reputation thresholds** — author has enough reps
- **File-op costs** — author can afford the operations
- **Merge compatibility** — commit merges cleanly with
  winner's tree (dry-merge per commit)
- **Genesis immutability** — `.freechains/config.lua` never
  changes
- **Mode enforcement** — per-commit tree diff vs parent;
  every changed path's operation must be permitted by the
  chain's `mode` field. See
  [2026-05-operation-modes-4way.md](2026-05-operation-modes-4way.md).

On first validation failure: discard that commit and
all subsequent loser commits.

## Merge (after validation)

Current implementation uses `git merge --no-commit`
followed by writing state files and `git commit`. This
produces a merge commit with two parents + state files
in a single commit. Equivalent to plumbing for the
non-conflict case.

State commits ("freechains: state") are created:
- After merge in recv (to persist replayed state)
- At genesis (initial pioneer state)

State files (`authors.lua`, `posts.lua`) are written to
disk on every command but only committed to git after
merges and at genesis. Post/like commits do NOT include
state files.

### State Commits as Checkpoints

State commits serve as **replay checkpoints**. The
merge-base always has state files in its tree (post/like
commits carry dirty state on disk, but the merge-base
is always reachable via a state commit in the shared
history). Current implementation loads state directly:

```lua
git show com:.freechains/state/authors.lua
git show com:.freechains/state/posts.lua
```

No backward walk is needed — state files are always
present in the tree at every commit (dirty but readable).

### Linearity Guarantee

Walking backwards from the merge-base is guaranteed to
be **linear** (no forks) because every merge is followed
by a state commit. This means a state commit always
appears between the merge-base and any merge point in
the shared history:

```
... → merge → state_commit → P1 → P2 → P3 (merge-base)
      ↑                                ↑
      never reached                     start walk back
```

The state commit acts as a **barrier** — it stops the
backward walk before encountering any non-linear
history (merge commits). Without this guarantee, the
backward walk could hit a merge commit with two parents,
making traversal order non-deterministic.

This is why "only after merge" is sufficient and
critical: it guarantees a checkpoint between the
merge-base and any fork in the DAG.

### Tie-Breaker

When two divergent branches have the same first-commit
author timestamp, the consensus winner is determined by
**commit hash** (lexicographic comparison). This ensures
both sides pick the same winner regardless of which is
local vs remote:

```
if l < r then
    fst, snd = loc, rem
elseif l > r then
    fst, snd = rem, loc
elseif loc < rem then       -- hash tie-breaker
    fst, snd = loc, rem
else
    fst, snd = rem, loc
end
```

## Trust Levels

See [replication.md](replication.md) for the full
owner/non-owner trust table. Owner-to-owner replication
skips freechains validation entirely. Non-owner
validation is future scope.

## Hard Fork Rule (NOT IMPLEMENTED)

A **hard fork** occurs when a local branch crosses either
activity threshold:

- **7 days** of elapsed time, OR
- **100 posts**

When this threshold is crossed, the local branch takes
priority and is ordered first — **regardless of the remote
branch's reputation**. The two peers permanently disagree
on consensus ordering and cannot converge.

### Branch Merge Ordering (precedence)

1. **Activity threshold** — if local branch crosses 7 days
   or 100 posts, it wins unconditionally (hard fork)
2. **Reputation** — whichever branch has more reputation in
   the common prefix is ordered first
3. **Tiebreaker** — lexicographical order of hashes

### Stable vs Unstable Consensus

- **Stable**: posts that have crossed the activity threshold
  are frozen permanently in the local ordering
- **Unstable**: recent posts (below the threshold) may still
  be reordered by incoming branches

Stable consensus freezes the order progressively — the
threshold operates backward from the newest local post,
freezing older posts as permanent. This creates checkpoints
for efficient reputation caching.

### Test Coverage

| Test              | Scenario                                    | Result   |
|-------------------|---------------------------------------------|----------|
| `n03_merge_ok`    | 6 concurrent posts, no time gap             | converge |
| `n04_merge_fail`  | 101 concurrent posts per peer (>100)        | diverge  |
| `n05_merge_fail`  | 8 days apart (>7 days)                      | diverge  |
| `n05_merge_ok`    | 3 pioneers, concurrent posts, within limits | converge |

### Reference

SBSeg-23 paper: `fsantanna-no/sbseg-23` — Section on
consensus merge rules.

## Paper vs Git-Based Conflict Rejection

The original paper rejects commits from the conflicting
commit onward — earlier commits in the losing branch are
kept. Git-based merge rejects the **entire** losing branch,
including commits before the conflict. This is because git
merge operates on whole branches, not individual commits.

See [merge.md](merge.md) §3 "Paper vs Git-Based Merge" for
the full comparison.

## Pipeline Summary

```
git fetch                      — git validates objects
    |
merge-base                     — find common ancestor
    |
consensus                      — earlier first-commit
                                 wins
    |
find last state checkpoint      — walk back from
                                 merge-base to nearest
                                 state commit or genesis
    |
load checkpoint state           — git_load from
                                 checkpoint ref
    |
replay checkpoint..merge-base   — bring state up to
                                 merge-base
    |
load winner state               — checkpoint + replay
    |
validate loser commits         — replay + dry-merge
    (on fail: discard rest)      per commit
    |
build merge commit             — git commit-tree
                                 (plumbing, no git merge)
    |
commit state                   — "freechains: state"
```
