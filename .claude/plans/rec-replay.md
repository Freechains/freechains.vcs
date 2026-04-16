# Recursive DAG Replay via backward `rec()`

## Context

The current `replay_remote` and `replay_loser` in
`src/freechains/chain/sync.lua` walk commits with
`git log --reverse --no-merges old..new`.
This is flat traversal:
order through previous-sync merges is undefined,
so two peers replaying the same range can produce
different `order.lua` vectors and diverge on state.

The fix is a recursive decomposition that respects
consensus ordering at every merge point in the DAG,
driven by git's native parent/merge-base queries —
no pre-built graph structure.

## Why recursive replay is needed

Flat `git log --no-merges` replay is broken for ranges
that contain merge commits from previous syncs:

1. **Non-determinism**:
   two peers replaying the same range get different
   traversal orderings through merges →
   different `order.lua` vectors →
   peers diverge on state.

2. **Broken winner-first rule**:
   flat replay ignores winner/loser ordering at inner
   merge points:
    - A loser's dislike may be applied **before** the
      winner's post, zeroing an author's reps and
      voiding a post that should survive.
    - An inner loser's validation failure **cascades**
      and kills valid commits in the tail after the
      merge.

Consensus itself is **immutable**: it is a pure
function of each merge's own common ancestor state
(`G_com`), so inner winners never flip under live G.
Recursion is needed only to produce the deterministic
winner-first traversal order, not to re-decide
consensus.

## Design: backward recursion

No forward graph. Walk backward from `rem` through
parents; apply on the return path.

### Primitives

| Primitive                         | Git call                                           |
|-----------------------------------|----------------------------------------------------|
| parents of a commit               | `git rev-list --parents -1 <hash>`                 |
| common ancestor of two commits    | `git merge-base <p1> <p2>`                         |
| in-range set for the top-level    | `git rev-list <com>..<rem>`                        |

### Algorithm

```
rec(G, tip, R):
    if not R[tip]: return                -- out of range or consumed
    R[tip] = nil                         -- mark consumed
    p1, p2 = parents(tip)
    if p2 == nil:                        -- linear
        rec(G, p1, R)
        F(G, tip)
    else:                                -- merge
        B = merge-base(p1, p2)
        rec(G, B, R)                     -- shared history (no-op if B out of range)
        w = consensus(G, B, p1, p2)
        if w == p1:
            rec(G, p1, R)                -- winner subtree first
            rec(G, p2, R)
        else:
            rec(G, p2, R)
            rec(G, p1, R)
        F(G, tip)                        -- merge commit last
```

### Why apply-on-return gives winner-first

- `rec(G, base, winner)` returns only after every F in
  the winner subtree has run.
- Then `rec(G, base, loser)` starts — loser's F's all
  come after winner's.
- `F(G, tip)` for the merge commit runs after both.

### Why inner consensus sees correct G

- `rec(G, B, R)` for the shared history applies every
  commit from `base` up to `B` before consensus runs.
- G reflects state *at B* — exactly what consensus
  needs.

### Entry point

```lua
replay_remote(G_rem, com, rem):
    R = in_range_set(com, rem)
    return pcall(rec, G_rem, rem, R)
```

## The `com` problem: rec-merge-base

`com = merge-base(loc, rem)` is too shallow in general.
When `rem` contains a merge whose parents' own
merge-base is *outside* `com..rem`, two problems arise:

### Problem 1: rec overshoots

```
         G
        / \
      a1   b1 ◄── com
        \ / \
         AB  b2 ◄── loc
         │
         c1 ◄── rem
```

`com..rem = {a1, AB, c1}`. Inner merge `AB` has
`merge-base(a1, b1) = G`, outside the range.
`rec(G, B=G, R)` returns immediately (G not in R), but
then `rec(G, b1, R)` via the loser subtree also hits
`b1` which is com (already applied locally, must not
be re-applied).

With `R[tip] = nil` consume-on-visit, this is correct
behavior — `b1` is simply absent from `R` and gets
skipped.

### Problem 2: determinism

`b1` is already in `G.order` (loaded from com's state
files). If AB's consensus picks `a1` as winner, the
canonical order has `a1` *before* `b1` — but B's local
order has `b1` fixed in place. Two peers produce
different `order.lua` vectors.

### Fix: deeper com

Compute `com` as the **recursive merge-base** —
deepest ancestor such that every merge in `com..rem`
has both parents inside the range. Iteratively push
`com` back through inner merge-bases until stable.

```
iter 1: com = merge-base(loc, rem)
iter n: for each merge M in com..rem:
            B = merge-base(M.p1, M.p2)
            if B is strict ancestor of com:
                com = B
        repeat until stable
```

With `com = G` in the example above, range becomes
`{a1, b1, AB, c1}`. Consensus at AB decides `a1`/`b1`
order consistently across all peers.

## Two-path pipeline

```
       replay_remote (in-memory, no git merges)
               |
               v
       consensus(G_com, com, loc, rem)
               |
   +-----------+-----------+
   | loc wins              | rem wins
   v                       v
 G_fst := live G_loc     G_fst := G_rem
 O_snd := G_rem.order    O_snd := local order
               |
               v
       replay_loser (trial-merge per commit)
               |
               v
         merge + state commit
```

- `replay_remote`:
  validates remote in memory only, no git merges.
  Uses backward `rec()` driven by `parents()` and
  `merge-base`.
- `replay_loser`:
  per-commit trial-merge into detached HEAD of
  winner tip, as today.
  Iterates `O_snd` in order — no graph walk, no
  consensus re-run.

## Consensus

```lua
local function consensus (G, com, a, b)
```

Algorithm (unchanged from current `sync.lua`):

1. Traverse `com..a` via `git log --format=%H`.
2. For each commit: `ssh.verify` → key or nil.
3. Collect unique signed keys for branch `a`.
4. Same for `com..b` → keys for branch `b`.
5. Sum `G.authors[key].reps` for each key set
   (0 if absent in `G`).
6. Higher sum wins → return that hash first.
7. Tie → hash tiebreaker (smaller wins).

At nested merges the caller passes the merge's own
**`B = merge-base(p1, p2)`** (state at that ancestor),
never live G.
Since B's G state is immutable by the time consensus
runs, inner consensus is immutable too.

## Nested-cascade failing test design

Goal:
demonstrate that flat replay produces wrong state
when a range contains a nested merge.

**Setup** (GEN_4: KEY1..KEY4 = 7500 each):

1. A creates chain.  B, C clone from A.
2. A: KEY1 dislikes KEY4 by 3 (inner A side).
3. A: KEY2 dislikes KEY4 by 3 (inner A side).
4. B: KEY4 posts `P_c` (inner B side).
5. A recvs B → inner merge M1 on A.
   A wins inner (sum 15000 > 7500).
   Under correct consensus `P_c` is voided on A.
6. C clones from A.
   C's replay walks `com..A_tip`, which contains M1.

**Assertion**:
C's `posts.lua` does **not** contain `P_c`,
and C's order matches A's order.

Under flat replay:
`P_c` may be applied before A's dislikes
(KEY4 still had 7500 reps at that point) →
`P_c` survives on C → test FAILS.

Under recursive replay:
winner-first at M1 → dislikes apply first →
`P_c` voided on C → test PASSES.

Implementation lives in `tst/consensus.lua`
(§ `Test 4: nested cascade`).

## Files to Modify

| File                             | Change                          |
|----------------------------------|---------------------------------|
| `src/freechains/chain/sync.lua`  | backward `rec()` + `parents()`  |
| `src/freechains/chain/sync.lua`  | `in_range` set gate             |
| `src/freechains/chain/sync.lua`  | `com = rec-merge-base(loc, rem)`|
| `src/freechains/chain/sync.lua`  | `replay_loser` unchanged        |
| `tst/cli-sync.lua`               | add 3-peer nested merge test    |

## Verification

```
make test T=cli-sync
make test T=consensus
```

## Done

- [x] `consensus(G, com, a, b)` — reps-sum +
  hash tiebreaker
  (`src/freechains/chain/sync.lua`)
- [x] Like replay via `diff-tree` + `git show`
  payload
- [x] Top-level consensus uses `consensus()`
- [x] Test 4 `nested cascade` added to
  `tst/consensus.lua` (driver test, failing under
  flat replay — confirmed)
- [x] `F(G, hash)` — per-commit apply helper,
  throws via `error(msg, 0)` on validation failure
- [x] `parents(tip)` — git `rev-list --parents -1`
  wrapper, returns `p1, p2`
- [x] `rec(G, base, tip)` — backward recursion,
  apply-on-return (first draft, no in-range guard)
- [x] `replay_remote(G_rem, com, rem)` — thin `pcall`
  wrapper around `rec`
- [x] Top-level call site updated (no `H`)
- [x] `graph()` / `walk()` / forward `BFS()` all
  removed from `sync.lua`

## Known bugs

- `rec` crashes when an inner merge's `merge-base` is
  outside `com..rem` (cli-sync step 3 "recv
  divergent"). Needs Step A fix.
- Consensus at inner merges uses live G, not a
  snapshot at `B`. Correct for freechains today (no
  pre-com dislikes), but not general.

## Next steps

Sequential; do not start step N+1 until step N is
green.

**▶ Resume here**: Step A — in-range guard.

### Step A — `in_range` set guard in `rec`

Fix the crash on cli-sync step 3.

- [ ] Compute `R = { [h] = true for h in rev-list com..rem }`
  in `replay_remote` before calling `rec`.
- [ ] Pass `R` as parameter to `rec`.
- [ ] At `rec` entry: `if not R[tip] then return end;
  R[tip] = nil` (consume).
- [ ] Drop `base` parameter (in-range set replaces
  the `tip == base` stop condition).
- [ ] Inner merges whose `B` is outside range: skip
  the shared-history `rec(G, B, R)` call silently —
  consensus still uses `B` as the common ancestor
  for `git log B..tip` walks.

Acceptance:

```
make test T=cli-sync       -- step 3 no longer crashes
```

### Step B — `com = rec-merge-base` for determinism

Fix non-determinism for scenarios where `b1`-like
commits (local-only posts before any sync) must be
reordered under consensus.

- [ ] New helper `rec_merge_base(loc, rem)`:
  iterate until stable — for each merge in the
  current `com..rem`, push `com` back to
  `merge-base(M.p1, M.p2)` if that's an ancestor of
  `com`.
- [ ] Call site: replace `com = merge-base(loc, rem)`
  with `com = rec_merge_base(loc, rem)`.
- [ ] Fast-forward check: swap `com == loc` for
  `git merge-base --is-ancestor loc rem`.
- [ ] `G_com` loading: state files exist at every
  state commit in freechains, so loading at the
  deeper `com` still works unchanged.

Acceptance:

```
make test T=cli-sync       -- all green
make test T=consensus      -- Test 4 passes
```

### Step C — nested-cascade test green

- [x] Test 4 added to `tst/consensus.lua`.
- [ ] Verify it passes after Steps A + B.

Acceptance:

```
make test T=consensus      -- Test 4 passes
```

### Step D — final verification

- [ ] `make test T=cli-sync`
- [ ] `make test T=consensus`
- [ ] Full suite: `make test`
- [ ] Update `## Done` section:
  mark Steps A–C as `[x]`.
