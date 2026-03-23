# Merge Defense: Dual-Election Protocol

## Problem

When two branches of a chain merge, the majority side can
outvote the minority side, effectively forcing unwanted
content on them. Both sides may want to refuse the merge,
but after merge, only the majority can reach quorum. This
is unfair — the power to refuse shouldn't depend on which
side has more reputation in the merged state.

## Solution: Dual-Election Merge Protocol

Every merge triggers **two independent elections**. Each
side votes on the other side's content. Refusal is
reversible — votes can keep flipping. But divergence
after refusal creates a de facto hard fork.

### Election mechanics

1. **Merge happens** — the merge commit (M1) is a
   permanent fact in the DAG. It is never erased.

2. **Two independent elections** — each side votes on
   the other side's **commit immediately before the
   merge** (the last state commit on that branch).

3. **Votes live in the merge zone** — as children of
   the merge commit.

4. **Reputation-weighted** — votes use pre-merge
   reputation from the voter's own side.

5. **>50% of weighted votes cast = refuse** — abstention
   is not acceptance. Only active like/dislike votes
   count.

6. **Elections are open forever** — votes can arrive at
   any time and flip the outcome.

### Election definition

```
        Branch A: ... → PA5 ──┐
                               ├→ M1 → [votes]
        Branch B: ... → SB3 ──┘
```

**Election 1:** Branch A votes on SB3 (Branch B's last
commit before merge)
- Voters: reputation holders from Branch A (pre-merge)
- Weighted by pre-merge rep on Branch A

**Election 2:** Branch B votes on PA5 (Branch A's last
commit before merge)
- Voters: reputation holders from Branch B (pre-merge)
- Weighted by pre-merge rep on Branch B

### Four outcomes

| A accepts B? | B accepts A? | Result                                          |
|---|---|---|
| yes | yes | Merge succeeds, M1 is active tip                            |
| yes | no  | Hard fork: A continues from M1, B continues from SB3        |
| no  | yes | Hard fork: A continues from PA5, B continues from M1        |
| no  | no  | Hard fork: both retreat to pre-merge tips, merge is dead     |

Any refusal produces a **hard fork** — the two sides
continue in different directions.

## Active Tip Retreat

When a side refuses, its active tip retreats to the
pre-merge point. New posts go there, not after the merge.

```
        PA5 ──────────────┐
                           ├→ M1 → R1 → R2 (refused by B)
        SB3 ──────────────┘
          ↑
          └── B's new posts go here
```

The merge zone (M1, votes) remains in the DAG but is a
dead branch from B's perspective. M1 is still active
from A's perspective (A accepted B).

## Reversibility

Elections are open forever. New votes can flip the
outcome:

```
        PA5 ──────────────┐
                           ├→ M1 → R1(refuse) → R2(refuse) → V1(accept) → V2(accept)
        SB3 ──────────────┘
          │
          └→ SB4 → SB5 (posted during refusal)
```

If votes flip, the refusal is reversed. But posts made
during the refusal period (SB4, SB5) remain where they
are — a new merge may be required to reunify.

## Re-Merge Protection

A re-merge that tries to circumvent an active refusal is
**invalid**. Detection rule: if there is content posted
after a refuse/dislike vote on a branch, the fork is
real and active. The branch has moved on — a new merge
cannot be created while the refusal stands.

A legitimate re-merge is only possible after votes flip
the refusal.

## Chain Identity After Fork

### The problem

Before a fork, there is one chain with one alias (e.g.,
`#sports`) and one genesis hash. After a refused merge,
two divergent branches both claim the same identity. The
genesis hash is identical for both (they share history up
to the merge). The alias is the same.

Peers need to distinguish "side A of `#sports`" from
"side B of `#sports`" for sync, storage, and routing.

### Per-user chain resolution

A node's **owner** (identified by public key) determines
which fork the node follows, based on the owner's vote.

But a node may host users from both sides of the fork.
And relay nodes (no stake in the chain) have no vote to
follow.

### Fork-path identity

Chain identity becomes a path: genesis + fork history.

```
#sports                     (original, pre-fork)
#sports/M1:A                (side A after merge M1)
#sports/M1:B                (side B after merge M1)
#sports/M1:A/M2:B           (nested: forked again)
```

Each fork appends a merge commit hash + side. This is a
history of choices. Relay nodes need to be told which
fork path to follow, or carry everything and let peers
filter.

### Open questions

- Can fork-path identity be simplified (e.g., a new
  genesis-like marker commit after the fork)?
- How do relay nodes behave — carry both sides, or
  choose?
- Does fork-path accumulate unboundedly for chains that
  fork repeatedly?
- Separate repositories per fork, or one repo with
  multiple refs?

## Relationship to Existing Mechanisms

| Mechanism              | Scope           | Timing      |
|------------------------|-----------------|-------------|
| 12h penalty on posts   | Individual post | Preventive  |
| Dislike on posts       | Individual post | Reactive    |
| Merge-witness timestamp| Detection       | At merge    |
| Consensus ordering     | Branch priority | At merge    |
| **Dual-election**      | **Entire merge**| **Reactive**|

The dual-election protocol operates at merge granularity.
It supersedes the merge voting mechanism described in
Section 4 of merge.md, which assumed a single election
per merge with first-parent bias.

## Related Plans

- [merge.md](merge.md) — Git merge internals, conflict
  resolution, earlier (superseded) merge voting design
- [new-merge.md](new-merge.md) — State branch design,
  consensus pipeline
- [threats.md](threats.md) — T1 (hard fork), T4a (merge
  divergence)
- [reps.md](reps.md) — Reputation system
- [consensus.md](consensus.md) — Fetch validation
