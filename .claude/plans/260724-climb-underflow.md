# Climb Underflow: `meet` descends below `oct` (`parents(nil)`)

## Symptom

A `sync send`/`recv` of a branch containing a "deep" merge crashes the
receiver:

```
ERROR : chain sync : sync.lua:300: attempt to concatenate a nil
value (local 'tip')
```

Surfaced in the README guide (`guide.sh`), final step: after A's recv
appends the community branch (fixed by
[260724-reorder-ancient](done/260724-reorder-ancient.md)), A's `sync
send` back to the hub `X` crashes X's replay.

## Root cause

`meet` (`sync.lua`) reconciles a merge by climbing from the merge-base
of its two parents:

```
meet(G, com, left, right, ...):
    up = merge-base(left, right)
    climb(G, com, up, false)      -- climb from `up` toward `com`
    ...
    climb(G, up, winner);  climb(G, up, loser)
```

`climb(G, com, cur)` walks parents UP until `cur == com`; a root commit
returns `parents = nil` -> `climb(G, com, nil)` -> `.. tip` on nil at
`parents()` (`sync.lua:300`).

This assumes `up` is a descendant of `com`. It is NOT with NESTED
merges: `meet` recurses `climb(G, up, side)` using its own fork `up` as
the com; if that side contains an INNER merge whose fork is DEEPER than
`up`, the inner `meet` computes `up' < up` and `climb(G, up, up')`
descends past `up` to a root.

Note: a SINGLE merge never underflows. `oct` is `merge-base --octopus`
of the `loc...rem` boundary, which lands exactly on that merge's fork,
so `up == com` and the climb returns immediately. The bug needs an
inner merge forking below an outer merge.

## Minimal reproduction (2 peers, 3 posts) — CONFIRMED

```
              genesis            (F1: deepest fork)
             /       \
        AW[K1]        CW[K2]
         |   \        /
         |    M1 = merge(CW, AW)      (M1 forks at genesis = F1)
         |         |
     takeover[K1]  |
          \        /
           M2 = merge(takeover, M1)  (M2 forks at AW = F2)
```

- A posts AW(K1); B posts CW(K2) — concurrent, fork at genesis (F1).
- B recv A -> inner merge `M1 = merge(CW, AW)`, fork = genesis (F1).
- A posts takeover (child of AW=F2); A recv B -> outer merge
  `M2 = merge(takeover, M1)`, fork = AW (F2). M2 nests M1 (F1 < F2).
- B recv A: climb M2 -> meet(up=F2) -> climb M1's side -> meet(com=F2,
  up=genesis=F1) -> `climb(F2, F1)` underflows -> `parents(nil)`.
  (Verified: `sync.lua:300`.)

B is the recv target (it already holds M1 but not takeover), so no
third peer is needed. Distinct files per post so the git merges succeed
(no content conflict) and `climb` reaches the bug.

## Test

`tst/climb-underflow.lua` (NOT yet wired into `make tests`; run via
`make T=climb-underflow test`). Asserts X's order contains `Q1` after
the recv:

- red now: recv crashes at `parents(nil)`
- green after fix

Wire it into the `tests:` target together with the fix.

## Fix part 1 — climb underflow (validated)

Global-`oct` floor. Precompute `anc = ancestors(oct)` once
(`git rev-list oct`); `climb` stops when `cur == com` OR `anc[cur]`.

- stops the underflow `climb(F2, seed)` (seed is an oct-ancestor)
- stops the erroneous re-apply `climb(seed, AW)` (AW == oct)
- CW (sibling of oct, not an ancestor) is still applied once

VALIDATED in scratch: eliminates the `parents(nil)` crash.

## Fix part 2 — ordering determinism (the real wall)

With the crash gone, the recv fails the strict state check:
`ERROR : chain sync : remote state mismatch`.

Diagnosed (scratch, dumped the diff): the ONLY difference is
`order.lua` positions [2]/[3] SWAPPED — the two concurrent posts
`CW`/`AW` (both @1100, forking at seed). `posts.lua` and `authors.lua`
(reps) are byte-identical.

Root: the relative order of two concurrent sibling posts is NOT a pure
function of the DAG:

- sender A fixed it via the reorder-append path (`fst`/`snd`) when it
  merged the community in
- receiver H re-derives it via climb + `consensus()` at the fork

The two mechanisms break the tie differently -> byte mismatch -> the
tamper-proof exact-match check (rightly) rejects it. Same CLASS as
[260723-consolidation-order](done/260723-consolidation-order.md), but
for MERGE ORDERING instead of consolidation.

So the underflow fix is necessary but not sufficient. To make divergent
nested-merge recvs pass, the merged order must be `oct`-independent:

| direction | idea |
|-----------|------|
| canonical order | one deterministic fold over the reachable post/like set (consensus + stable hash tiebreak) that climb and reorder both produce identically |
| single floor | always re-derive from a fixed anchor (genesis / deepest fork), not the per-recv `oct` |
| (rejected) relax check | compare semantic state not bytes -- weakens tamper-proofing |

Need: confirm whether `consensus()`'s tiebreak is being applied
consistently, and whether the reorder-append path can be replaced by
the same canonical fold climb uses.

## Dig results (2026-07-24) — it's a redesign, not a patch

Traced all derivations of the CW/AW pair:

| derivation           | CW/AW order       |
|----------------------|-------------------|
| B (creates M1)       | CW before AW      |
| H community (from B) | CW before AW      |
| A (stores M2)        | CW before AW      |
| H climb re-derive    | **AW before CW**  |

Only H's climb flips it. Cause: `oct = AW` (octopus-boundary picks the
fork of the NEW commits = takeover's fork), and `G_oct = AW`'s state
`[seed, AW]` PREDATES CW. climb inherits that order and can only append
CW after AW. Diff is purely `order.lua` [2]/[3]; reps identical.

Rejected fixes (validated in scratch):
- `(time, hash)` sort of `G.order` -> DISCARDS reps-consensus. NO.
- deepen `oct` below nested forks -> STILL crashes: `meet` recurses with
  `com = local up` (=AW), not the global oct, so inner M1 still
  underflows at seed. And it double-applies AW (outer meet applies it,
  inner M1 meet re-climbs it).

Root: `climb`/`meet` assume (a) every merge fork is >= the segment
floor and (b) no commit is visited twice. Nested RE-merges (a merge
whose side contains a deeper merge) break both.

Correct direction (design change to `sync.lua` re-derivation):
1. collect the post/like set reachable from `rem` but not `oct`
2. order it by a canonical consensus fold (reps, then hash tiebreak)
   with a `visited` guard so nothing is applied twice
3. ensure the SENDER's stored order uses the same fold, so the strict
   byte-check passes

This subsumes part 1 (no recursion underflow) and part 2 (order becomes
a pure function of the DAG) while KEEPING reps-consensus.

## Design (2026-07-24)

### Two derivation paths that must agree

The strict state check compares a receiver's RE-DERIVED state against
the sender's STORED bytes. But merged order is produced by TWO different
code paths:

- ff path (`sync.lua:354-371`): the `climb`-derived `G_rem` IS the
  answer, checked byte-for-byte.
- divergent path (`sync.lua:377-456`): `fst` (winner) state + `O_snd`
  (loser order) appended via git merges — the REORDER path.

The sender A built M2 via the divergent/reorder path; the receiver B
validates via `climb` (ff path). The two disagree on nested-merge order.

### Why no local fix works

`meet(com, left, right)` sets `up = merge-base(left, right)` and recurses
`climb(up, arm)`. For `M2 = merge(takeover, M1)`, `up = AW`, and the arm
`M1 = merge(CW, AW)` re-merges `up` (AW) with `CW`, which forks at
genesis < up. So:

- the inner meet's floor is `AW` (the outer `up`), never the global oct
  -> deepening oct does NOT help (validated: still crashes).
- `AW` is already EMITTED by the time M1 asks to order `CW` vs `AW`
  -> append-only order cannot reposition it -> `CW` lands after `AW`,
  but canonical is `CW` before `AW`.

Binary merge-tree recursion is insufficient: `M2` effectively reconciles
THREE branches (takeover, AW-line, CW-line) forking at TWO depths
(AW, genesis). Pairwise `merge-base(takeover, M1) = AW` hides the deeper
CW fork.

### Target invariant

ONE canonical order = pure function of (DAG, reps-at-forks),
independent of oct and of which peer derives it. Both the store and the
re-derivation must emit it. Reps-consensus preserved (no time/hash
shortcut).

Requirement that forces the shape: nothing may be emitted until every
fork that could order a commit before it is resolved. => reconcile
DEEPEST fork first (bottom-up), from a floor below ALL forks in the
divergent region.

### Candidate algorithms

- **B1 — bottom-up fold**: collect all merges in the region; reconcile
  from the deepest merge-base up. At each fork run `consensus` and
  concatenate winner-then-loser; a `visited` set prevents re-emit.
  Preserves current semantics for simple forks; fixes nesting.
- **B2 — comparator sort**: define `before(X,Y)` = winner side at
  `merge-base(X,Y)` (tie: hash); topologically stable-sort the reachable
  post/like set. Cleanest spec, but must prove transitivity and cost
  (per-pair merge-base + reps-at-fork).
- **B3 — unify paths only**: make the divergent/reorder path ALSO run
  the canonical fold to store, and `climb` reuse the SAME function, so
  sender and receiver can't diverge by construction.

Lean: **B1 + B3** — one `derive(tips)` fold used by BOTH the ff check
and the divergent store; reconcile bottom-up with a visited guard.
Significant rewrite of `sync.lua`'s `climb`/`meet` + the reorder block.

### B1 fold — CONCRETE (traced, matches canonical)

A canonical order provably EXISTS: B, A, H-community all produced
`[.., CW, AW, day1, day7, takeover]` via non-underflowing paths. The
fold that reproduces it:

```
-- oct = deepest fork in region (octopus of all merge-bases of merges
-- reachable from tips). G, visited, order seeded from G_oct (canonical
-- prefix, since oct is below all forks).
for M in merges_reachable_from_tips (TOPOLOGICAL order, ancestors first):
    p1, p2 = parents(M)
    fork   = merge-base(p1, p2)
    emit(fork)                    -- ensure trunk to fork emitted
    w, l   = consensus(fork, p1, p2)
    emit(w); emit(l)              -- winner side then loser side
for tip in tips: emit(tip)        -- remaining above the last merge

emit(h):                          -- oldest-first, visited-guarded
    walk h's ancestors down to the deepest UNVISITED post/like,
    skipping visited and already-processed merges; apply + append
    each post/like once; mark visited.
```

Fixes both bugs: deepest-fork-first => no underflow and no stale
inheritance (CW/AW ordered together at genesis before anything above);
`consensus()` unchanged => reps-consensus preserved.

### B3 — unify

`derive(tips)` replaces: (a) `climb`/`meet` in the ff-check path, and
(b) the append-ordering in the divergent/reorder block (git merge
commits still created for the DAG; STATE/order come from `derive`).
Sender store and receiver check run the SAME code => can't diverge.

### PROTOTYPE VALIDATED (2026-07-24, scratch)

Implemented `derive` in scratch (reusing in-scope `consensus`/`commit`/
`parents`), derived from genesis root over BOTH tips:

```
Gd = state at root; visited = Gd.order
for M in `rev-list --topo-order --reverse --merges loc rem`:  -- ancestors first
    p1,p2 = parents(M); fork = merge-base(p1,p2)
    emit(fork); w,l = consensus(Gd, fork, p1, p2); emit(w); emit(l)
-- virtual top merge of the two recv tips:
fork = merge-base(loc, rem); emit(fork)
w,l = consensus(Gd, fork, loc, rem); emit(w); emit(l)

emit(h): if visited[h] return; emit(p1); emit(p2); visited[h]=true;
         commit(Gd, h)   -- appends post/like to Gd.order; merge/state noop
```

Results:
- nested case: `derive` == A's canonical order  (bug FIXED)
- simple fork: `derive` == existing algo order   (NO regression, byte-eq)

Key correction vs first attempt: must derive over BOTH `loc` and `rem`
(the merge commit doesn't exist yet during a divergent recv) + a final
VIRTUAL reconcile of `loc`/`rem`.

### Open impl details
- topo-order the merges cheaply: `git rev-list --topo-order --merges`
  (reverse for ancestors-first).
- `emit()` must stop cleanly at processed merges (their subtree already
  visited) -- guaranteed by ancestors-first processing.
- confirm `derive` reproduces EXISTING simple-fork order byte-for-byte
  (regression: run full `make tests`).

Open questions for implementation:
- efficient "deepest fork in region" without O(n^2) merge-bases
- reps-at-fork are already in `G` during a single fold pass if we go
  bottom-up (compute the shared trunk once, then each arm)
- does the git commit topology (real merge commits) still get written
  the same, or only the state files?

## Checklist (revised)

- [x] Repro test (red) — minimized to 2 peers / 3 posts (AW, CW, takeover)
- [x] Diagnose: nested-merge underflow + oct-dependent ordering
- [x] DESIGN the canonical consensus fold (visited-guarded)
- [x] Prototype validated (nested == canonical; simple == existing)
- [x] Implement in `sync.lua`: `climb`/`meet` -> `derive` fold; divergent
      path stores `G_rem` (canonical); drop `G_fst` state-building
- [x] Smoke (scratch): nested fixed (B==A order); simple fork converges;
      hard-fork local-first preserved; likes/reps ok
- [x] `climb-underflow.lua` wired into `make tests`
- [ ] `make tests` green (USER to run)
- [ ] `./guide.sh` completes (USER to run)

## Checklist

- [x] Add `tst/climb-underflow.lua` (red: reproduces the crash)
- [x] Confirm crash (verified in scratch: `sync.lua:300` parents(nil))
- [x] Re-confirm via `make T=climb-underflow test` (red at l.115)
- [ ] Fix `meet`/`climb` underflow
- [ ] Flip test to green; wire into `make tests`
- [ ] `./guide.sh`: A's final `sync send` succeeds end to end

## References

- [260724-reorder-ancient.md](done/260724-reorder-ancient.md) — the fix
  that exposed this (A's branch gained the deep merge)
- [2026-06-14-readme.md](2026-06-14-readme.md) — Hard Forks section
- [sync.md](sync.md) — sync algorithm
