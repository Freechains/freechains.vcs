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
The pre-merge-commit hook (see merge-hook.md) runs as a
final safety net before creating the merge commit.

## Trust Levels

| Peer type | Fetch validation   | Merge              |
|-----------|--------------------|--------------------|
| Owner     | no-op (full trust) | direct merge       |
| Non-owner | signatures, rep, DAG | merge after pass |

Owner-to-owner replication skips freechains validation
entirely — both peers share the same key material and
trust each other fully.

Non-owner validation is future scope.

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

A **hard fork** occurs via community vote on a branch
divergence. See merge.md for the full mechanism.

### Two regimes

| Vote difference | Action                          |
|-----------------|---------------------------------|
| Below threshold | Consensus rule (deterministic)  |
| Above, one-sided| Veto — drop the minority branch |
| Above, balanced | Hard fork — chain splits in two |

When a hard fork triggers:
- The fork point (last common ancestor) becomes the root
  of two new chain identities
- Each peer follows its **owner's vote** (the local
  repo's signing key determines the side)
- Peers who didn't vote follow the majority

### Legacy thresholds (activity-based)

The original hard-fork triggers were activity-based:

- **7 days** of elapsed time, OR
- **100 posts**

These remain as **automatic hard-fork signals** — if a
local branch crosses either threshold, the peer treats it
as an implicit vote for its own branch. The vote-based
mechanism subsumes these.

### Branch Merge Ordering (precedence)

1. **Vote-based hard fork** — if the vote difference
   crosses the threshold, the chain splits (merge.md)
2. **Activity threshold** — if local branch crosses 7 days
   or 100 posts, implicit hard fork vote
3. **Reputation** — whichever branch has more reputation in
   the common prefix is ordered first
4. **Tiebreaker** — lexicographical order of hashes

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

## Pipeline Summary

```
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

## Related Plans

- [merge.md](merge.md) — Owner-driven vote, veto, hard fork
- [merge-hook.md](merge-hook.md) — Pre-merge-commit hook
- [threats.md](threats.md) — T1 partition fork, T1a boundary
- [7-day.md](7-day.md) — Activity threshold analysis
