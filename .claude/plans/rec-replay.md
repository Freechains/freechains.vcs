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

The cascade problem is the concrete rule violation:
a post valid under correct winner-first ordering gets
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
  `graph()` so inner merges produce a deterministic
  winner-first order.
- `replay_loser`:
  per-commit trial-merge into detached HEAD of
  winner tip, as today (`sync.lua:126`).
  Iterates `O_snd` in order — no graph walk, no
  consensus re-run.
  `O_snd` is already deterministic (built by
  `replay_remote` or taken from local order) and
  consensus of inner merges cannot change.

## Fork anatomy

```
                          left branch
              ┌── l1 ── ... ── l2 ──┐
              │  (first)    (tip)  │
              │                    │
      node ───┤                    ├─── join ───▶
       ↑      │                    │     ↑
      (fork)  │                    │   (merge)
              │  (first)    (tip)  │
              └── r1 ── ... ── r2 ──┘
                          right branch
```

| Name        | Role                                          |
|-------------|-----------------------------------------------|
| `node`      | fork point (already applied)                  |
| `l1` / `r1` | first children of `node` — branch entries     |
| `l2` / `r2` | branch tips — parents of `join`               |
| `join`      | merge commit                                  |

## Algorithm

### Signature

```lua
local function replay_remote (G_rem, H, start, stop)
```

| Arg     | Role                                    |
|---------|-----------------------------------------|
| `G_rem` | state being built (starts as `G_com`)   |
| `H`     | graph (shared, immutable)               |
| `start` | node to begin walking from              |
| `stop`  | end node (nil = walk to leaf)           |

### Invariant

`start` is already applied
(or is `com`, the base state `G_rem` starts from).
Callee applies all nodes from `start`'s children up to
`stop` (exclusive).

### Pseudocode

```
node = start
while node ~= stop:
    k = #childs(node)
    if k == 0: return                     -- leaf
    if k == 1:
        c = only_child
        if c == stop: return
        apply(G_rem, c)
        node = c
    else:
        l1, l2, r1, r2, join = walk(H, node)
        w, _ = consensus(G_rem, node, l2, r2)
        cw, cl = (w == l2) and (l1, r1)
                               or (r1, l1)
        apply(G_rem, cw)
        replay_remote(G_rem, H, cw, join)
        apply(G_rem, cl)
        replay_remote(G_rem, H, cl, join)
        if join == stop: return
        apply(G_rem, join)
        node = join
```

### Top-level call

```
replay_remote(G_rem, H, com, nil)
```

### Helpers

| Helper              | Status   | Purpose                           |
|---------------------|----------|-----------------------------------|
| `walk(H, node)`     | new      | returns `l1, l2, r1, r2, join`    |
| `consensus()`       | exists   | `sync.lua:8-42`                   |
| `apply(G_rem, c)`   | exists   | current `replay_remote` body      |

### Error paths

Bad signature / invalid like metadata / etc:
`apply()` returns error → abort recursion, propagate
error to top-level caller (same as today's flat loop).

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

At nested merges the caller passes the merge's own
**`G_com`** (state at its common ancestor), never live
G.
Since `G_com` is immutable, inner consensus is
immutable too — it cannot invert.

## 3-peer failing test design

Goal:
demonstrate that flat `git log --no-merges` replay
produces wrong state when nested merges exist.
Flat traversal interleaves inner winner and inner
loser commits, letting loser dislikes void winner
posts (cascade), while recursive replay applies all
inner-winner commits before any inner-loser commits.

**Setup** (GEN_4: KEY1..KEY4 = 7500 each):

1. A creates chain. Clone to B and C.
2. A: KEY1 posts P1 (inner A side).
3. B: KEY2 dislikes KEY1 by 3 (inner B side).
4. C recvs A, C recvs B → inner merge on C.
   A wins (KEY1 reps 7500 > KEY2's 0 after own
   dislike cost) — P1 is inner winner.
5. B: KEY3 posts P2, KEY4 posts P3 (after step 3).
6. A recvs B → outer merge.
   Suppose B wins outer.
   A's branch (with inner merge from step 4) is
   the outer loser.
7. A re-applies outer loser via `replay_loser`.
   Inner winner-first order: P1 applies before
   KEY2's dislike → P1 survives.
   Flat order: dislike may apply first → P1 voided.

**Assertion**:
A's state has P1 as a valid post after step 7.
With flat replay:
P1 may be voided (KEY1 reps zeroed by KEY2's
dislike applied out of order).
Test FAILS under flat, PASSES under recursive.

## Files to Modify

| File                             | Change                         |
|----------------------------------|--------------------------------|
| `src/freechains/chain/sync.lua`  | add `graph()` local            |
| `src/freechains/chain/sync.lua`  | rewrite `replay_remote` on graph|
| `src/freechains/chain/sync.lua`  | `replay_loser` stays flat,      |
|                                  | iterates `O_snd`                |
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

### Step 2 — adapt `replay_remote` for recursion

- [ ] Add local `walk(H, node)` in `sync.lua`:
  returns `l1, l2, r1, r2, join` for a fork at `node`
  (see § Fork anatomy).
- [ ] Rewrite `replay_remote` (`sync.lua:48-119`) with
  the signature and pseudocode in § Algorithm:

    ```lua
    local function replay_remote (G_rem, H, start, stop)
    ```

- [ ] Top-level caller:
  build `H = graph(REPO, com, rem)` once, then call
  `replay_remote(G_rem, H, com, nil)`.
- [ ] Preserve existing error paths
  (invalid signature, invalid like metadata, etc.) —
  abort recursion and propagate upward.
- [ ] Keep `apply` logic unchanged;
  factor out of the flat loop into a helper if needed.

Acceptance:

```
make test T=cli-sync       -- all green
```

### Step 3 — keep `replay_loser` flat, driven by `O_snd`

- [ ] `replay_loser` does **not** need `walk()` or
  `graph()`.
  Consensus is immutable (pure function of each
  merge's `G_com`), so inner ordering on the loser
  branch is already fixed by `O_snd`.
- [ ] Iterate `O_snd` in order
  (`sync.lua:126-207` pattern):
    - `git merge --no-commit <hash>` for every
      non-state commit (as today `sync.lua:157-168`).
    - On conflict: `merge --abort`, return error.
    - Otherwise `commit -m 'x'`, then
      `apply(G_fst, entry)`.
- [ ] Keep the detached-HEAD setup and the
  `__close`-based `checkout main` cleanup
  (`sync.lua:129-136`).
- [ ] Simplify the `O_snd[]` index hunt
  (`sync.lua:138-145`) if still needed.

Acceptance:

```
make test T=cli-sync       -- all green
```

### Step 4 — 3-peer nested merge test

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

### Step 5 — final verification

- [ ] `make test T=git-merge`
- [ ] `make test T=cli-sync`
- [ ] Full suite: `make test`
- [ ] Update `## Done` section:
  mark steps 1–4 as `[x]`.
