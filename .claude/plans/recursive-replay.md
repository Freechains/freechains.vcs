# Recursive Replay

## Context

Replace flat `git log --no-merges` replay in
`sync.lua`. Flat replay produces non-deterministic
ordering through inner merges, causing peers to
diverge on state.

## Key Insight

Consensus at any merge uses merge-base state
(immutable prefix reps). Inner merge ordering is
deterministic from the merge-base — live G during
replay cannot change it. Winner's effects only affect
**validity** (cascade discard), not order.

This splits replay into two modes with different
trust assumptions.

## Two replay modes

| Call site           | Mode              | Trust     |
|---------------------|-------------------|-----------|
| Remote validation   | graph + recursion | untrusted |
| Loser replay        | G.order + tail    | trusted   |

### Mode 1: verification replay (remote, sync.lua:204)

Remote's committed G.order cannot be trusted before
validation (remote could have tampered). Must compute
consensus order independently.

1. `graph(REPO, com, rem)` → forward DAG
2. Walk from root:
   - Linear (1 child): apply in sequence
   - Fork (2 children) or merge ahead (nparents > 1):
     find merge-base of branches, run
     `consensus(base, p1, p2)` using base-state,
     recurse winner then loser, continue from merge
3. On any apply failure: stop, error

Consensus at inner merges uses merge-base state
(loaded from merge-base's state files — always valid
since state commits carry G.order, authors, posts).

### Mode 2: order replay (loser, sync.lua:230)

After remote validation, loser's G.order is trusted
(validated for remote; local for local). Use it
directly — no graph walk.

1. `order_snd = git show snd:.freechains/state/order.lua`
   (tip's committed G.order from its last state commit —
   post/like commits don't modify state files)
2. `R = git rev-list com..snd` — commit set in range
3. Filter order_snd to hashes in R → ordered prefix
4. Linear tail: commits in R not in order_snd, via
   `git log --no-merges last_state..snd` (linear since
   state commits only happen after merges)
5. Sequence = prefix + tail
6. Iterate: apply each on G_winner
7. On apply failure: stop, cascade discard (rest of
   sequence dropped)

## graph(dir, fr, to)

Local to sync.lua. Enhanced from tst/git-merge.lua:

```lua
G[hash] = {
    hash     = hash,
    time     = time,     -- author timestamp
    childs   = {},
    parents  = {},       -- parent hashes (from git)
    nparents = N,        -- merge if > 1
}
```

One git command:
`git log --topo-order --reverse`
`--format='%H %at %P' fr..to`

## find_merge(G, child)

From fork child, follow `childs[1]` with depth
counting:
- 2 children (nested fork) → depth++
- nparents > 1 at depth 0 → found
- nparents > 1 at depth > 0 → depth--

## walk(G_state, dag, hash, stop)

Top-down recursive decomposition for Mode 1.
Scans ahead for next structural event before
processing commits.

- Linear (no event ahead): apply directly (skip
  state/merge trailers)
- Fork (2 children): find_merge, inner consensus on
  base-state, recurse winner then loser, continue
  from merge
- Merge ahead (nparents > 1 on linear path): get two
  parents, `git merge-base` for common ancestor,
  load base-state, inner consensus, recurse into
  both branches, continue from merge

A merge is a merge — two parents, one merge-base.
Same handling whether fork point is inside or
outside the graph range.

Returns (ok, last, err) for error propagation.

## Inner consensus

Uses merge-base state (load authors.lua + order.lua
from base via `git show base:...`). Prefix reps from
base decide winner, same rule as outer consensus.
Deterministic and base-state-immutable.

## Implementation Steps

| Step | Description                   | Status      |
|------|-------------------------------|-------------|
| 1    | graph() in sync.lua           | [ ] pending |
| 2    | find_merge()                  | [ ] pending |
| 3    | walk() — Mode 1               | [ ] pending |
| 4    | G.order-based replay — Mode 2 | [ ] pending |
| 5    | Wire Mode 1 to sync.lua:204   | [ ] pending |
| 6    | Wire Mode 2 to sync.lua:230   | [ ] pending |
| 7    | Rename G_end → G_fst          | [ ] pending |
| 8    | Test: make test T=cli-sync    | [ ] pending |

## Files to modify

| File             | Place          | Change               |
|------------------|----------------|----------------------|
| `chain/sync.lua` | new local func | graph()              |
| `chain/sync.lua` | new local func | find_merge()         |
| `chain/sync.lua` | new local func | walk() (Mode 1)      |
| `chain/sync.lua` | replay() split | Mode 1 and Mode 2 entry points |
| `chain/sync.lua` | line 204       | Call Mode 1 (verify) |
| `chain/sync.lua` | line 218-230   | Call Mode 2, rename G_end→G_fst |
