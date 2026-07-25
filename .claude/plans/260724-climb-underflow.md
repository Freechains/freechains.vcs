# Climb Underflow: nested-merge reconciliation

## Status: SIMPLE FIX in working tree — pending `make tests` + `./guide.sh`

Decision: adopt the SMALL fix (guards on the original `climb`), accept a
known limitation on large time gaps, and document that limitation with a
RED test. The committed `derive` fold (commit c5a8555) is being REPLACED
by the simple fix in the working tree (uncommitted). START AT
"## NEXT STEP".

## Symptom

`sync recv`/`send` of a branch with NESTED merges crashed the receiver:

```
ERROR : chain sync : sync.lua:300: attempt to concatenate a nil value (local 'tip')
```

Surfaced in `guide.sh` final step (A's `sync send` back to hub X).

## Root cause

`meet(com, left, right)` recursed `climb(up, side)` using its LOCAL fork
`up` as the floor. A nested inner merge forking DEEPER than `up` made
`climb(up, up')` with `up' < up` descend past a root -> `parents(nil)`.
Plus a shared commit (the outer fork) could be visited/applied twice.

## Minimal reproduction — `tst/climb-underflow.lua` (2 peers, 3 posts)

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

A posts AW, B posts CW (fork at genesis); B recv A -> M1; A posts
takeover, A recv B -> M2 (nests M1, F1 < F2); B recv A -> crash.
Test asserts B's order contains `takeover`. GREEN with the simple fix.

## SIMPLE FIX (adopted) — two guards on the original `climb`

Keeps the original `climb`/`meet` AND the original reorder path. Only
`climb`'s stop condition changes (~21 lines, `src/freechains/chain/sync.lua`):

```
local visited = {}                       -- seed from G_oct.order
for _, h in ipairs(G_rem.order) do visited[h] = true end
local function ancestor(a,b) ... merge-base --is-ancestor a b end

climb = function (G, com, cur, beg)
    if cur == com or visited[cur] or ancestor(cur, com) then return end
    ... (unchanged meet/recursion) ...
    visited[cur] = true
    commit(G, cur, beg, false)           -- was true; re-derivation, not first-receipt
end
```

- `ancestor(cur, com)` -> stops the underflow (no descent below the floor).
- `visited` (from G_oct + per-emit) -> no double-apply of the shared fork.
- Result reproduces the sender's `[AW, CW, takeover]` -> consistent.

Validated in scratch: 2-peer nested, 3-peer (small gaps), simple fork,
hard-fork 7-day, likes/reps -- all consistent (A==peer).

## KNOWN LIMITATION — large time gap — `tst/climb-underflow-gap.lua` (RED)

The simple fix keeps TWO derivation paths (`climb` ff-check from the
shallow `oct`; reorder-append for the divergent store). When a nested
merge spans a LARGE time gap (crossing the 24h maturation/consolidation
window, as the real guide does), the two paths DIVERGE and the strict
check rejects the recv:

```
ERROR : chain sync : remote state mismatch
```

`tst/climb-underflow-gap.lua` reproduces it (same nested topology, `day7`
~7 days out) and asserts H==A order. RED today. NOT wired into
`make tests` (run: `make T=climb-underflow-gap test`).

The full fix that makes it green is the single canonical `derive` fold
(below), which was PROTOTYPED + IMPLEMENTED (commit c5a8555) and passes
this large-gap case (A==H, byte-identical). We chose the simple fix for
now; adopt `derive` if/when the gap case must pass.

## Reference: the `derive` fold (full fix, commit c5a8555)

Derive from the genesis ROOT over BOTH tips; reconcile every merge
bottom-up (ancestors-first) via `consensus`; `visited` guard; then the
top-level loc/rem split (`fst` wins). One function feeds BOTH the ff
check and the divergent store, so sender/receiver can't diverge -- which
is exactly why it survives the maturation gap. Cost: re-derives from
genesis each recv. Diff was ~142 lines (vs 21 for the simple fix).

## NEXT STEP (start here on the other machine)

1. Ensure the working tree has the simple fix: `git diff 0eb800c --
   src/freechains/chain/sync.lua` should show ONLY the ~21-line guard
   change (NOT the derive fold). New file: `tst/climb-underflow-gap.lua`.
   (The committed HEAD still has `derive`; the simple fix is uncommitted.)
2. RUN `make tests` -- must be green incl. `climb-underflow`,
   `consensus`, `fork-7-days`, `fork-100-posts`, `reorder-ancient`.
3. RUN `make T=climb-underflow-gap test` -- expect RED (documents the
   known large-gap limitation).
4. RUN `./guide.sh`. NOTE: the guide uses REAL ~7-day gaps, so it likely
   hits the same `remote state mismatch` as the gap test. If so, that is
   the KNOWN LIMITATION -- either accept it (guide won't fully complete)
   or switch to the `derive` fold (commit c5a8555) which handles it.
5. Commit the chosen approach; move plan to `done/` if satisfied.

## Checklist

- [x] Repro test (red) — 2 peers / 3 posts
- [x] Diagnose: nested-merge underflow + oct-dependent ordering
- [x] Simple fix (climb guards) in working tree
- [x] Failing test for the large-gap limitation (`climb-underflow-gap.lua`)
- [ ] `make tests` green (incl. `climb-underflow`)  <-- NEXT
- [ ] `make T=climb-underflow-gap test` RED (expected)
- [ ] `./guide.sh` — decide: accept gap limitation or switch to `derive`
- [ ] commit; move plan to `done/`

## References

- [260724-reorder-ancient.md](done/260724-reorder-ancient.md) — exposed this
- [2026-06-14-readme.md](2026-06-14-readme.md) — Hard Forks section
- [sync.md](sync.md) — sync algorithm
