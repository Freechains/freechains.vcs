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
- **Genesis immutability** — genesis.lua never changes

On first validation failure: discard that commit and
all subsequent loser commits.

## Merge (after validation)

No `git merge` call. Merge commit is built via git
plumbing (`commit-tree` with two parents: winner HEAD
+ validated loser pointer). This avoids working tree
conflicts entirely.

State commits ("freechains: state") are created:
- Before send (so receiver gets our state)
- After recv (to persist replayed state)

## Trust Levels

See [replication.md](replication.md) for the full
owner/non-owner trust table. Owner-to-owner replication
skips freechains validation entirely. Non-owner
validation is future scope.

## Hard Fork Rule

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
load winner state              — from tree or disk
    |
validate loser commits         — replay + dry-merge
    (on fail: discard rest)      per commit
    |
build merge commit             — git commit-tree
                                 (plumbing, no git merge)
    |
commit state                   — "freechains: state"
```
