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

## Checklist (revised)

- [x] Repro test (red) — minimized to 2 peers / 3 posts (AW, CW, takeover)
- [x] Diagnose: nested-merge underflow + oct-dependent ordering
- [ ] DESIGN the canonical consensus fold (visited-guarded)
- [ ] Implement in `sync.lua`; sender + receiver agree byte-for-byte
- [ ] `climb-underflow.lua` green; `make tests` green
- [ ] `./guide.sh` completes

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
