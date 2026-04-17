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

## Urgent (blocks correctness)

These two issues block case 4 (diverge) and edge
diamonds.
Must be fixed before Steps A/B in *Next steps*.

### U1. Oldest-is-merge overshoot

Current `com = oldest^` in `sync.lua` takes the
*first parent only*.
If the oldest commit in `loc..rem` is itself a merge,
its second-parent chain leaks into `com..rem` but
`com` sits above it on one side.
`rec_meet` at the oldest merge calls `rec_climb` with
`up = true merge-base`, which is a strict ancestor of
`com` → `rec_climb` walks past `com` into its
ancestors → crash.

```
              R                 ← true recursive merge-base
             / \
           a     b               ← both in com..rem if oldest=M
           │\   /│
           │ \ / │
           │  X  │               ← X = loc  (merge(a, b))
           │     │
           └──M──┘               ← M = merge(a, b), oldest in loc..rem
               │
               c                 ← rem

  loc..rem       = {c, M}
  com = M^       = a             ← first parent only
  range com..rem = {c, M, b}     ← b sneaks in
  M.merge-base(a, b) = R         ← strict ancestor of com, outside range
```

Fix: `com` = **recursive merge-base** — push back
iteratively until every merge in `com..rem` has both
parents inside the range (or equal to `com`).

```
iter 1: com = oldest^ (current code)
iter n: for each merge M in com..rem:
            B = merge-base(M.p1, M.p2)
            if B is strict ancestor of com:
                com = B
        repeat until stable
```

### U2. Double-apply of commits shared with loc history

With `com` pushed deeper (e.g. `com = R` above),
commits in `com..rem` may also be ancestors of `loc`
(e.g. `a`, `b`).
Remote replay applies them to `G_rem` starting at
`com`;
a subsequent loser walk over `G_rem.order` would
re-apply them to `G_fst = live G_loc` → double count.

Fix: precompute `R = in_range_set(com, rem)` once,
then `rec_climb` gates on `R[tip]`:

- `R[tip] == nil` → skip (out of range or already
  consumed)
- after visit: set `R[tip] = nil` (consume-on-visit)

Loser walk reuses the same set so commits already in
loc's history are skipped.

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
  hash tiebreaker, scoped inside the recv block's
  do-block
- [x] `parents(tip)` — git `rev-list --parents -1`
  wrapper, returns `p1, p2`
- [x] `commit(G, hash)` — per-commit helper
  (renamed from `F`); throws on validation failure.
  `merge` flag deferred (see Step A)
- [x] `rec_climb(G, com, cur)` — single-tip backward
  walker; delegates merges to `rec_meet`
- [x] `rec_meet(G, com, left, right)` — merge-point
  helper: walks shared history, runs consensus,
  recurses winner-then-loser
- [x] Backward recursion replaces forward BFS; no
  graph/H/walk structures
- [x] `outer_merge_base` logic inlined in main:
  parent of oldest commit in `loc..rem`
- [x] Fast-forward check uses
  `git merge-base --is-ancestor loc rem` (no longer
  compares `com == loc`)
- [x] Cases 1, 2, 3 complete in main:
  1. unrelated genesis → ERROR
  2. rem ancestor of loc → early-out
  3. loc ancestor of rem → `pcall(rec_climb)` +
     `git merge --ff-only`
- [x] Test 4 `nested cascade` added to
  `tst/consensus.lua`

## Known bugs

- See `## Urgent` — U1 (oldest-is-merge overshoot)
  and U2 (double-apply) must be fixed first.
- `rec_climb` / `rec_meet` don't accept or forward
  the `merge` flag to `commit` — loser-side tree
  walks can't trigger per-commit git-merge yet.
- `replay_loser` still present in `sync.lua`;
  not yet subsumed by `rec_meet(merge=true)`.
- Case 4 tail still references `fst` / `merge` /
  `G_fst` / `G_rem` / `replay_loser` from the flat
  era — undefined / stale; whole block needs rewrite.

## Next steps

Sequential; do not start step N+1 until step N is
green.

**▶ Resume here**: Step U1 — recursive merge-base
for `com`.

### Step U1 — recursive merge-base for `com`

Fix the oldest-is-merge overshoot (see `## Urgent`
U1).

- [ ] Replace the `com = oldest^` inline block with
  an iterative push-back: for each merge `M` in
  `com..rem`, if `merge-base(M.p1, M.p2)` is a
  strict ancestor of `com`, set `com` to it; repeat
  until stable.
- [ ] Reload `G_com` from the new `com` after push
  stabilizes.

Acceptance:

```
make test T=cli-sync       -- still green
make test T=consensus      -- no regression
```

### Step U2 — in-range consume-on-visit set

Fix the double-apply (see `## Urgent` U2).

- [ ] Compute `R = in_range_set(com, rem)` =
  `git rev-list com..rem` as a hash-set.
- [ ] `rec_climb(G, com, cur, R)` gates on
  `R[cur]`; after visit sets `R[cur] = nil`.
- [ ] Threads `R` through `rec_meet` as well.
- [ ] Loser walk reuses the same `R` so
  loc-ancestor commits are skipped.

Acceptance:

```
make test T=consensus      -- Test 4 passes
```

### Step A — propagate `merge` flag

- [ ] Add `merge` parameter to `rec_climb(G, com,
  cur, merge)` and `rec_meet(G, com, left, right,
  merge)`.
- [ ] Forward the flag through every internal call.
- [ ] `rec_climb` passes `merge` to `commit(G, cur,
  merge)`.
- [ ] Case 3 call (fast-forward): `pcall(rec_climb,
  G, com, rem, false)` — explicit false.
- [ ] Case 4 call: still `pcall(rec_meet, G, com,
  loc, rem, false)` for now; Step B restructures.

Acceptance:

```
make test T=cli-sync       -- still green (no
                              behavior change yet)
```

### Step B — rewire case 4 tree-side

Option picked: bundle the detach into `rec_meet` via
a `top` flag.

- [ ] `rec_meet(G, com, left, right, merge, top)`:
  at top-level, run winner rec with `merge=false`,
  `git checkout --detach winner`, `<close>` cleanup
  `checkout main`, then loser rec with `merge=true`.
- [ ] Inner `rec_meet` (top=false) keeps uniform
  `merge` flag for both sub-recs (inherits caller's).
- [ ] Main case 4: single call
  `pcall(rec_meet, G, com, loc, rem, false, true)`.
- [ ] Replace the old fst/merge/G_fst block with a
  final merge commit + state commit.
- [ ] Delete `replay_loser`.

Acceptance:

```
make test T=cli-sync       -- all green
```

### Step D — final verification

- [ ] `make test T=cli-sync`
- [ ] `make test T=consensus`
- [ ] Full suite: `make test`
- [ ] Update `## Done` section:
  mark Steps U1, U2, A, B as `[x]`.
