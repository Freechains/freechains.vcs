# Recursive DAG Replay for Consensus-Ordered Traversal

## Context

The current `replay(G, old, new)` in `sync.lua` uses
`git log --reverse --no-merges old..new` to walk commits.
This is wrong when the range contains merge commits from
previous syncs with other peers. At each merge, two
parent branches exist -- their traversal order must follow
the consensus rule (earlier first-commit wins, hash
tie-breaker). The current flat traversal has undefined
order through merges, causing peers to compute different
state due to order-dependent cap interactions in `apply()`.

## Approach

Replace `replay()` with a recursive decomposition that
respects consensus ordering at every merge point in the
DAG.

### Key Guarantee

State commits after every merge ensure that between any
two merge points, the DAG is **linear**. This bounds
recursion depth to the number of merge levels (not
commit count).

### Algorithm

```
replay(G, old, new):
    list = []
    collect(list, old, new)
    for each entry in list:
        apply(G, entry)

collect(list, old, new):
    if old == new: return

    merge = find last merge in old..new
        (git rev-list --topo-order --merges
         --max-count=1 old..new)

    if no merge:
        collect_linear(list, old, new)
        return

    p1, p2 = parents of merge
    base = merge-base(p1, p2)

    collect(list, old, base)          -- shared prefix

    fst, snd = consensus(base, p1, p2)  -- winner/loser
    collect(list, base, fst)          -- winner branch
    collect(list, base, snd)          -- loser branch

    collect_linear(list, merge, new)  -- linear tail
                                      -- (skips state)

collect_linear(list, old, new):
    git log --reverse --no-merges old..new
    skip trailer == "state"
    append post/like entries to list

consensus(base, p1, p2):
    first commit timestamp comparison
    hash tie-breaker if equal
```

### Checkpoint walk (chk..com)

Stays as-is (linear). The state commit barrier guarantees
no merges in this range.

### Winner/loser paths

Keep two paths:
- **local wins**: G = G_com, replay(G, com, loc),
  replay(G, com, rem)
- **remote wins**: G = G_rem (deep copy + remote replay),
  replay(G, com, loc)

G_rem is built as deep copy of G_com + replay remote.
Both paths use recursive replay (not disk state).

## Files to Modify

| File | Change |
|------|--------|
| `src/freechains/chain/sync.lua` | Replace `replay()` with recursive `collect` + `collect_linear` + `consensus` helper |

## Determinism Proof

Both peers find the same merge commits (immutable git
objects), compute the same merge-base, apply the same
consensus rule (timestamps + hashes are immutable),
recurse into the same sub-ranges in the same order,
and collect the same linear segments. Therefore both
peers produce the same `apply()` call sequence.

## Recursion Depth

Bounded by number of nested merge levels in the range,
not by commit count. Each merge adds 3 recursive calls
(prefix, winner, loser) + one `collect_linear`. Linear
segments are handled iteratively via `git log`.

## Edge Cases

- **Fast-forward (com == loc)**: no merges in range,
  falls through to `collect_linear`
- **No previous syncs**: purely linear, `collect_linear`
  handles it
- **Nested merges**: recursive decomposition peels off
  outermost merge first, recurses into sub-ranges
- **State commits in linear segment**: skipped by
  trailer check in `collect_linear`

## Verification

```
make test T=cli-sync
```

Step 3 (divergent + bilateral sync) validates that both
sides converge to identical state (bit-equal diff).

Future: add a test with 3 peers (A syncs with C, then
A syncs with B) to exercise nested merge replay.

## Done

- [x] `consensus(base, p1, p2)` helper (first-commit
  timestamp + hash tie-breaker)
- [x] `collect_linear(list, old, new)` — linear segment
  walk (post + like entries, skips state)
- [x] `collect(list, old, new)` — recursive DAG
  decomposition at merge points
- [x] `replay(G, old, new)` — collect then apply (with
  beg detection for likes)
- [x] Top-level consensus replaced with `consensus()` call
- [x] Like replay via `diff-tree` + `git show` payload

## TODO

- [ ] Verify: `make test T=cli-sync`
- [ ] Test: 3-peer nested merge replay
