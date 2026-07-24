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

## Fix direction (not yet done)

In `meet`, `climb(G, com, up)` must not walk below `com`. Options:

- if `up` is an ancestor of `com` (`merge-base(up, com) == up` and
  `up ~= com`), clamp: skip the `climb(G, com, up)` (com already covers
  it) or climb from `com` instead.
- more directly: make `climb` stop when `cur` is an ancestor of `com`
  (not only when `cur == com`).

Need to confirm the reconciliation state stays correct when the two
merge sides fork below `oct` (their shared history is already in
`G_oct`).

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
