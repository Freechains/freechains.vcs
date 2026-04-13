# Recursive Replay

## Context

Replace flat `git log --no-merges` replay in
`sync.lua` with graph-based recursive traversal
respecting consensus ordering at inner merge points.

## Approach

1. Build forward DAG via enhanced `graph()`
2. Walk graph from root, applying commits directly
3. At forks (2 children) or merges (nparents > 1):
   get merge-base, consensus, recurse winner then
   loser
4. No separate collect phase — apply during traversal

## graph(dir, fr, to)

Local to sync.lua.
Enhanced from `tst/git-merge.lua`:

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

Top-down recursive decomposition.
At each position, scan ahead for the next structural
event before processing commits:

- **Linear** (no merge/fork ahead): apply each commit
  directly (skip state/merge trailers)
- **Fork** (2 children): find corresponding merge via
  `find_merge`, inner consensus (hash comparison),
  recurse winner then loser, continue from merge
- **Merge ahead** (nparents > 1 on linear path): get
  two parents, `git merge-base` for common ancestor,
  inner consensus, recurse into both branches from
  effective base, continue from merge

A merge is a merge — two parents, one merge-base.
Same handling whether the fork point is inside or
outside the graph range.

Returns (ok, last, err) for error propagation.

## replay(G, com, fst, snd)

New body:
1. `graph(REPO, com, snd)` → DAG
2. Detached checkout at fst (if trial-merge needed)
3. `walk(G, dag, com, nil)` — traverse DAG, apply
   each commit directly
4. Checkout main (cleanup via `__close`)

Per-commit logic unchanged: trailer check, signature
verification, like metadata reading, apply(), trial
merge.

## Inner consensus

Hash comparison (smaller wins) for inner merges.
All peers compare the same immutable hashes →
deterministic ordering.

## Implementation Steps

| Step | Description                | Status      |
|------|----------------------------|-------------|
| 1    | graph() in sync.lua        | [ ] pending |
| 2    | find_merge()               | [ ] pending |
| 3    | walk()                     | [ ] pending |
| 4    | Replace replay() body      | [ ] pending |
| 5    | Test: make test T=cli-sync | [ ] pending |

## Files to modify

| File             | Place          | Change           |
|------------------|----------------|------------------|
| `chain/sync.lua` | new local func | graph()          |
| `chain/sync.lua` | new local func | find_merge()     |
| `chain/sync.lua` | new local func | walk()           |
| `chain/sync.lua` | replay()       | Graph + walk     |
