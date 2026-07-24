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

## Minimal reproduction (3 peers) — CONFIRMED

```
            AW[K1] (F2) ------------------ takeover[K1] --\
           /       \                                       M2  (fork = AW = F2)
 seed[K1] (F1)      M1 -- day1[K2] -- day7[K2] -----------/
           \       /   (M1 = merge(CW, AW), fork = seed = F1)
            CW[K2]
```

- A: seed, AW(K1).  B: CW(K2) — AW, CW fork at seed (F1).
- B recv A -> inner merge `M1 = merge(CW, AW)`, fork = seed (F1).
- B posts day1, day7 (community advances past M1).
- H recvs community (day7); A (still at AW=F2) posts takeover.
- A recv community -> outer merge `M2 = merge(takeover, day7)`,
  fork = AW (F2). M2's community side nests M1 (forks at F1 < F2).
- H recv A: climb M2 -> meet(up=F2) -> climb community side re-enters
  M1 -> meet(com=F2, up=seed=F1) -> `climb(F2, F1)` underflows ->
  `parents(nil)` -> crash. (Verified: `sync.lua:300`.)

Distinct files per post so git merges succeed (no content conflict) and
`climb` reaches the bug.

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
