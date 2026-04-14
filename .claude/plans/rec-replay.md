# Recursive DAG Replay via graph()

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
driven by a forward graph built with
`git rev-list --topo-order --reverse --parents`.

## Why recursive replay is needed

Flat `git log --no-merges` replay is broken for ranges
that contain merge commits from previous syncs:

1. **Non-determinism**:
   two peers replaying the same range get different
   traversal orderings through merges →
   different `order.lua` vectors →
   peers diverge on state.

2. **Broken consensus rules**:
   flat replay ignores winner/loser ordering at inner
   merge points:
    - A loser's dislike may be applied **before** the
      winner's post, zeroing an author's reps and
      voiding a post that should survive.
    - An inner loser's validation failure **cascades**
      and kills valid commits in the tail after the
      merge.
    - Inner consensus inversion
      (where live G changes which side wins a nested
      merge)
      never happens — flat replay does not re-evaluate
      consensus.

The cascade problem is the concrete rule violation:
a post valid under correct consensus ordering gets
voided because flat replay processes commits in the
wrong order.
That is not just different state — it is wrong state.

## Graph helper

`graph(dir, fr, to)` builds a forward DAG from
`git rev-list --topo-order --reverse --parents fr..to`.

```lua
-- Returns flat table:
--   G = { root=fr, [hash] = { hash=hash, childs={...} } }
local function graph (dir, fr, to)
```

Properties:

| Property      | Value                                      |
|---------------|--------------------------------------------|
| Direction     | forward (parent → child via `childs`)      |
| Root          | `G.root == fr`                             |
| Node shape    | `{ hash, childs }`                         |
| Linear node   | `#childs == 1`                             |
| Fork node     | `#childs > 1`                              |
| Leaf          | `#childs == 0` (tip, `to`)                 |
| Pass          | single, zero conditionals                  |

Reference implementation and tests live in
`tst/git-merge.lua` (scenario 4, nested merge lab).
Target location in production:
`src/freechains/chain/sync.lua` (local function).

### Key Guarantee

State commits after every merge ensure that between
two state commits the DAG is **linear**.
So recursion depth is bounded by the number of
merge levels, not by commit count.

## Algorithm

Forward walk of `G`, starting at `G.root`, following
`childs`:

```
walk(list, G, node, stop):
    while node ~= stop:
        k = #G[node].childs
        if k == 0:
            return                      -- leaf
        if k == 1:
            append(list, child)
            node = child
        else:
            -- fork: find the join (merge with
            -- both fork branches as parents)
            join = find_join(G, node)
            p1, p2 = parents_of(join)
            fst, snd = consensus(G_live, node,
                                  p1, p2)
            walk(list, G, fst_child_of(node, fst),
                  join)                 -- winner
            collect_loser(list, node, snd)
                                        -- loser
                                        -- (trial
                                        -- merge)
            append(list, join)
            node = join

replay(G, old, new):
    g = graph(REPO, old, new)
    list = []
    walk(list, g, g.root, nil)
    for each entry in list:
        apply(G, entry)
```

- `find_join(G, fork)`:
  merge commit reachable from `fork` whose parents
  are both descendants of `fork`
  (the matching merge for this fork).
- `fst_child_of(node, tip)`:
  the child of `node` that is an ancestor of `tip`.
- Linear segments between forks/joins walk iteratively.
- State commits (`Freechains: state` trailer) are
  skipped at `apply` time
  but kept in `G.order`.

## Two-path pipeline (kept side by side)

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
  Becomes recursive by driving traversal with
  `graph()`.
- `replay_loser`:
  per-commit trial-merge into detached HEAD of
  winner tip, as today (`sync.lua:126`).
  Becomes recursive by driving traversal with
  `graph()` so inner merges re-evaluate consensus
  under live `G_fst`.

Both replays share the `walk()` kernel;
they differ only in the per-entry action
(pure `apply` vs `merge --no-commit` + `apply`).

## Consensus

```lua
local function consensus (G, com, a, b)
```

Algorithm (matches current `sync.lua:8-42`):

1. Traverse `com..a` via `git log --format=%H`.
2. For each commit: `ssh.verify` → key or nil.
3. Collect unique signed keys for branch `a`.
4. Same for `com..b` → keys for branch `b`.
5. Sum `G.authors[key].reps` for each key set
   (0 if absent in `G`).
6. Higher sum wins → return that hash first.
7. Tie → hash tiebreaker (smaller wins).

At nested merges the caller passes the **live `G`**
(not `G_com`), so inner consensus re-evaluates with
ongoing state.

## Determinism proof

Both peers:

- build the same `graph()` (immutable git objects),
- visit the same root, same `childs` order
  (sorted by hash),
- resolve every fork via the same `consensus(G,
  com, p1, p2)` on the same live `G`,
- recurse winner before loser in the same order,
- walk linear segments identically.

Therefore both peers produce the same `apply` call
sequence and the same `order.lua`.

## Recursion depth

Bounded by the number of nested merge levels in the
range, not by commit count.
Each fork adds one recursive call for the winner
subgraph and one for the loser subgraph;
linear segments iterate.

## Edge cases

| Case                          | Handling                          |
|-------------------------------|-----------------------------------|
| Fast-forward (com == loc)     | graph has only linear nodes       |
| No previous syncs             | graph is purely linear            |
| Nested merges                 | recursion descends per fork       |
| State commits in linear path  | skipped by trailer check at apply |
| Inner consensus inversion     | live G at fork re-decides         |

## 3-peer failing test design

Goal:
demonstrate that flat `git log --no-merges` replay
produces wrong state when nested merges exist.
The outer winner's effects invert the inner
consensus, resurrecting previously-revoked commits.

**Setup** (GEN_4: KEY1..KEY4 = 7500 each):

1. A creates chain. Clone to B and C.
2. A: KEY2 posts P1, KEY4 posts P2, KEY2 posts P3.
3. C syncs with A → C has P1, P2, P3.
4. B: KEY1, KEY2, KEY3 each dislike KEY4 by 3.
5. A recvs B → inner merge.
   B wins (22500 > 15000).
   P2 fails (KEY4=0), P2+P3 voided.
   P1 survives.
   Rejected P2, P3 orphaned on A but still on C.
6. C: dislikes KEY1 and KEY3 heavily
   (inverts inner consensus — makes A's side >
    B's side).
7. C recvs A → outer merge.
   C's branch wins.
8. C recvs B → gets B's dislikes.
9. With recursive replay:
   C re-evaluates inner merge using live G
   (after C's effects).
   Inner consensus inverts (A wins).
   B's dislikes are the loser.
   KEY4 never zeroed → P2, P3 are valid.

**Assertion**:
C's state has P2 and P3 as valid posts.
With flat replay:
P2 rejected (KEY4=0 from B's dislikes applied in
arbitrary order).
Test FAILS under flat, PASSES under recursive.

## Files to Modify

| File                             | Change                         |
|----------------------------------|--------------------------------|
| `src/freechains/chain/sync.lua`  | add `graph()` local            |
| `src/freechains/chain/sync.lua`  | rewrite `replay_remote` on graph|
| `src/freechains/chain/sync.lua`  | rewrite `replay_loser` on graph |
| `tst/cli-sync.lua`               | add 3-peer nested merge test    |

## Verification

```
make test T=cli-sync
make test T=git-merge
```

## Done

- [x] `consensus(G, com, a, b)` — reps-sum +
  hash tiebreaker
  (`src/freechains/chain/sync.lua:8-42`)
- [x] `graph(dir, fr, to)` — forward DAG builder
  (`tst/git-merge.lua:30-52`, scenario 4 tests)
- [x] Like replay via `diff-tree` + `git show`
  payload (`sync.lua:74-98`, `sync.lua:171-189`)
- [x] Top-level consensus uses `consensus()`
  (`sync.lua:277`)

## Next steps

Sequential; do not start step N+1 until step N is
green.

### Step 1 — move `graph()` into src

- [ ] Copy `graph(dir, fr, to)`
  from `tst/git-merge.lua:30-52`
  into `src/freechains/chain/sync.lua`
  as a file-local function (above `consensus`).
- [ ] Keep the copy in `tst/git-merge.lua` untouched
  (its scenario 4 tests must still pass).
- [ ] Touch no call sites yet.

Acceptance:

```
make test T=git-merge      -- still green
make test T=cli-sync       -- still green
```

### Step 2 — graph helpers

- [ ] Add local `find_join(G, fork)` in `sync.lua`:
  walk `childs` from `fork`,
  return the first merge node whose two parents are
  both descendants of `fork`.
- [ ] Add local `fst_child_of(G, node, tip)`:
  return the child of `node` that is an ancestor of
  `tip`.
- [ ] Extend `tst/git-merge.lua` scenario 4:
  assert `find_join(G, H1) == M2`
  and `find_join(G, fork_at_a1) == M1`.

Acceptance:

```
make test T=git-merge      -- new asserts pass
```

### Step 3 — `walk()` kernel

- [ ] Add local
  `walk(list, g, node, stop, action)` in `sync.lua`.
    - Linear (`#childs == 1`):
      `action(list, child)`,
      advance `node`.
    - Fork (`#childs > 1`):
      `join = find_join(g, node)`;
      read `join`'s two parents `p1, p2`;
      `fst, snd = consensus(G_live, node, p1, p2)`;
      recurse winner side
      (`walk` from `fst_child_of(node, fst)`
       to `join`);
      recurse loser side
      (same shape, different `action`);
      `action(list, join)`;
      `node = join`.
    - Leaf (`#childs == 0`):
      return.
- [ ] No callers yet; exercise indirectly through
  step 4 and step 5.

Acceptance:
compiles, no callers broken
(`make test T=cli-sync` still green).

### Step 4 — rewrite `replay_remote` on `walk()`

- [ ] Replace the flat loop in `replay_remote`
  (`sync.lua:48-119`) with:

    ```
    g = graph(REPO, com, rem)
    walk(list, g, g.root, nil, action_remote)
    for each entry in list: apply(G, entry)
    ```

- [ ] `action_remote`:
  pure — no git merges,
  just `apply(G, entry)` with the same `post` / `like`
  / `state` dispatch as today.
- [ ] Preserve existing error paths
  (invalid signature, invalid like metadata, etc.).

Acceptance:

```
make test T=cli-sync       -- all green
```

### Step 5 — rewrite `replay_loser` on `walk()`

- [ ] Replace the flat loop in `replay_loser`
  (`sync.lua:126-207`) with the same `walk()`
  driver,
  using `action_loser`:
    - `git merge --no-commit <hash>` for every
      non-state commit (as today `sync.lua:157-168`).
    - On conflict: `merge --abort`, return error.
    - Otherwise `commit -m 'x'`, then
      `apply(G_fst, entry)`.
- [ ] Keep the detached-HEAD setup and the
  `__close`-based `checkout main` cleanup
  (`sync.lua:129-136`).
- [ ] Drop the `O_snd[]` index hunt
  (`sync.lua:138-145`) — graph walk replaces it.

Acceptance:

```
make test T=cli-sync       -- all green
```

### Step 6 — 3-peer nested merge test

- [ ] Add a new section in `tst/cli-sync.lua`
  that reproduces §3-peer failing test design
  verbatim (GEN_4, 9 steps).
- [ ] Assert on C:
  P2 and P3 appear as valid posts in `posts.lua`,
  KEY4 reps > 0,
  diff against A is bit-equal.

Acceptance:

```
make test T=cli-sync       -- new test passes
```

### Step 7 — final verification

- [ ] `make test T=git-merge`
- [ ] `make test T=cli-sync`
- [ ] Full suite: `make test`
- [ ] Update `## Done` section:
  mark steps 1–6 as `[x]`.
