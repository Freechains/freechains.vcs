# Consensus: Fetch Validation Pipeline

## Git's Built-in Validation (fetch)

On `git fetch`, git validates automatically:

- **Object integrity** — SHA hash of every object matches
  content
- **Object graph** — commits reference valid parents, trees,
  blobs
- **Transfer protocol** — packfile checksums, no corruption

These guarantees are free — no freechains code needed.

## Freechains Validation (between fetch and merge)

After fetch, before merge, freechains must validate
consensus-level rules that git doesn't know about:

- **Signature verification** — GPG signatures on commits
- **Reputation thresholds** — author has enough reputation
- **DAG rules** — block acceptance per chain type
- **Genesis immutability** — genesis.lua must never change
  after chain creation

## Merge (after validation)

`git merge` integrates validated commits.
The `pre-merge-commit` hook (see [merge.md](merge.md) §3)
runs as a final safety net before creating the merge commit.

## Trust Levels

See [replication.md](replication.md) for the full
owner/non-owner trust table. Owner-to-owner replication
skips freechains validation entirely. Non-owner validation
is future scope.

## Dry-run Merge Check

Before the real merge, a dry-run verifies mergeability:

```
git merge --no-commit --no-ff FETCH_HEAD
```

- Exit code 0 → merge would succeed (clean)
- Exit code != 0 → merge would fail (conflict or
  unrelated histories)

After checking: `git merge --abort` to clean up.
Only proceed to real merge if dry-run passes.

Note: `--abort` is only needed when `MERGE_HEAD` exists
(success or conflict). Unrelated histories rejection
leaves no merge state — no abort needed.

| Dry-run result       | MERGE_HEAD | Abort needed |
|----------------------|------------|--------------|
| Success (code 0)     | yes        | yes          |
| Conflict (code 1)    | yes        | yes          |
| Unrelated (code 128) | no         | no           |

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
reset local time effects       — reset local/now.lua
                                 (see local-staging.md)
    |
git fetch                      — git validates objects
    |
freechains                     — validate signatures,
                                 reputation, DAG
    |
git merge --no-commit --no-ff  — dry-run merge check
git merge --abort              — clean up dry-run
    |
git merge                      — real merge
```

Note: local time effects write to `local/` files
(untracked) on every chain command (local-staging.md).
Since `local/` is git-excluded, no cleanup is needed
before merge.
