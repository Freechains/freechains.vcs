# Bug: reps debt (vote beyond balance)

## Summary

The like/revoke reputation gate checks only that the voter has
`reps > 0`, not that they can afford the vote magnitude. A voter
with any positive balance can spend an arbitrarily larger amount,
driving their own `reps` deeply and permanently negative.

`common.lua` apply (like/revoke branch):

```lua
local reps = (G.authors[T.sign] and G.authors[T.sign].reps) or 0
if (not self_revoke) and reps <= 0 then        -- BUG: presence, not affordability
    return false, "insufficient reputation"
end
...
G.authors[T.sign].reps = reps - math.abs(T.n)  -- no floor -> goes negative
```

## Root cause

- Gate is spec rule 4.a ("`>= 1` rep to act") — presence only.
- The mutation deducts the FULL `abs(T.n)` with no lower bound.
- `T.n = ARGS.number * C.reps.unit`; `ARGS.number` is any
  positive integer (`positive` converter, no upper bound).

## Is 1 trillion debt possible? YES

- `reps.unit = 1000`, so `like N` costs `N * 1000` internal.
- Voter needs only `reps > 0` to pass the gate.

```
KEY has 1 ext (1000 internal)
like 1000000000  ->  T.n = 1e9 * 1000 = 1e12
reps = 1000 - 1e12  =  -999999999000   (~ -1 trillion internal)
```

- Reachable for any `N` up to ~9.2e15 (beyond that `N*1000`
  overflows int64 — a second latent bug, see below).

## Impact

| effect | detail |
|-----------------------|-------------------------------------------|
| Permanent debt        | recovery adds only `reps.cost` (1000) per maturation event; -1e12 needs ~1e9 events -> account bricked |
| Reps destruction      | target is capped at `reps.max` (30 ext); a huge like burns the voter's balance with ~no benefit |
| Self-brick vector     | one command permanently disables an account |
| (latent) int overflow | astronomically large `N` overflows `N*1000` (int64), flipping sign -> corrupts vote direction |

Not a target-inflation exploit (author cap blocks that), but a
self-destruction / reps-burn bug. Conservation holds only until
the cap clips the target, after which reps are lost.

## Fix

Gate on **affordability**, not presence:

```lua
if (not self_revoke) and reps < math.abs(T.n) then
    return false, "insufficient reputation"
end
```

- Subsumes the old check (`|T.n| >= 1000`, so `reps <= 0` still
  rejected).
- After the deduct, `reps >= 0` always -> no debt.
- `self_revoke` stays free/ungated (no deduction, no debt).

Consider also (separate, optional): bound `ARGS.number` (e.g.
`<= reps.max` ext) to kill the int-overflow path early.

## Spec impact

`reps.md` rule 4.a becomes "enough reps to cover the vote
magnitude", not just ">= 1". Update the like/dislike formulas'
gate wording.

## Test to add (proposed)

Home: `tst/cli-reps.lua`, "Gate check" section (funded pioneers
already set up there).

- `debt-overspend-rejected`
  - KEY1 pioneer has 30 ext; `like 31 post <P> --sign KEY1`
  - FAIL: `ERROR : chain like : insufficient reputation`
  - assert `reps author KEY1` unchanged (no partial deduct)

- `debt-exact-spend-ok`
  - KEY1 `like 29 post <P>` (affordable) -> succeeds
  - assert `reps author KEY1 >= 0`

- `debt-never-negative` (regression)
  - after the overspend attempt, assert every author's
    `reps >= 0` (parse `reps authors` / state posts.lua)

- (optional) `debt-huge-number-rejected`
  - `like 1000000000 post <P>` -> insufficient reputation,
    reps unchanged (documents the 1-trillion case)

## Progress

- [x] fix gate: `reps < math.abs(T.n)` in `common.lua`
- [x] fixed the `reps.md` like/dislike **cost formula** too — it
      said `liker.reps -= 1000` (fixed) but code deducts the full
      `N*1000`; only the code's version conserves reps
- [x] added tests: `cli-reps.lua` "Debt gate" (overspend
      rejected, reps unchanged, never negative)
- [ ] (optional / won't-do) cap `ARGS.number` for the
      int-overflow path — the affordability gate already rejects
      any un-affordable N, so overflow only affects rolled-back
      commits; low value
- [x] all tests pass (2026-07-22)

## Cross-references

- `common.lua` apply like/revoke gate + mutation.
- `reps.md` — rule 4.a, like/dislike transfer formulas.
- `260721-revoke.md` — `self_revoke` is the one exempt (free)
  path; must stay exempt.
