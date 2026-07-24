# Reorder Replay Rejects Ancient Loser Commits (`too old`)

## Symptom

A divergent `sync recv`/`send` prints:

```
ERROR : invalid post : too old
```

(or `invalid like : too old`) and silently drops the losing branch's
commits from the merged order.

Surfaced in the README guide (`guide.sh`), Hard Forks section: peer `A`
recvs the hub `X` and rejects Bob's old `like` `f133ef1`, so `A`'s
`list order` ends up missing the entire community branch.

## Not hard-fork specific

The failing code (`sync.lua:378-456`) is the **second replay phase**
that appends the losing branch `snd` onto the winner `fst`.
`fst` is chosen by **either** `hardfork()` **or** `consensus()`, so a
plain consensus divergence with a >1h wall-clock gap triggers it too.
The hard fork only made the gap obvious (7 days).

## Root cause

The reorder loop replays `snd` commits through `apply()`:

```
sync.lua:386   now = NOW(loc)          -- fst tip time (far ahead)
sync.lua:420   for _, hash in ipairs(O_snd) do
sync.lua:440       ok, err = pcall(commit, G_fst, hash)   -- -> apply()
```

`apply()`'s monotonic guard rejects any commit older than the current
`now` minus the drift tolerance:

```
common.lua:96   if time < G.now - C.time.diff then
                    return false, "too old"      -- diff = 1h
```

Because `G_fst.now` is seeded from the winner's advanced tip, the
loser's legitimately-older commits (already validated once in the
`climb` pass) fail this check and are dropped.

The guard exists to reject clock drift on **genuinely new** posts on
receipt; it must not fire while **re-ordering already-known** commits.

## Failing test (drives the fix)

New `tst/reorder-ancient.lua`, pure consensus path (no hard fork):

```
GEN_2 (KEY1=15, KEY2=15); KEY2 likes seed -> KEY1 > KEY2
A: post alpha  @now=2000       (KEY1, winner side, own file)
A: post gamma  @now=2000000    (KEY1, advances A tip.now past +1h)
B: post beta   @now=2000       (KEY2, ancient, own file, no conflict)
B sync send -> A               (A wins by reps; fst=A, now=2000000)
  reorder replays beta@2000 : 2000 < 2000000-3600 -> "too old"
```

Assert `beta`'s hash appears in `A`'s `list order`.
Currently FAILS (beta dropped); the fix flips it green.

Distinct files per post avoid a git `merge --no-commit` **content**
conflict (`sync.lua:425`, err `content conflict`), so the loop reaches
the `apply()` monotonic guard.

## Fix options

| option | note |
|--------|------|
| seed reorder `now` from the common ancestor `oct`, not `NOW(loc)` | localized to the reorder block; monotonicity still holds within `snd` |
| pass a `reorder` flag to `apply()` that skips the `too old` guard | commits already validated in `climb`; guard is redundant here |

Recommendation: the `reorder` flag — the intent ("do not re-validate
freshness while re-ordering") is explicit, and it cannot mask drift on
first receipt (which still runs through `climb`).

## Scope note

Pre-existing, independent of `260723-consolidation-order.md` (that was a
byte-divergence in derivation; this is order-dropping on divergent
merge). Any divergence with a >1h winner/loser time gap hits it.

## Checklist

- [x] Add failing `tst/reorder-ancient.lua` + Makefile line
- [x] Confirm it fails: `make T=reorder-ancient test` (line 80, beta)
- [x] Fix reorder replay: `reorder` flag skips the `too old` guard
      (`apply` `common.lua`, threaded via `commit(..., reorder)`)
- [x] `make tests` green (incl. new test)
- [x] refactor: flag renamed `reorder`→`monotonic`, moved out of `T`
      into an `apply` param, both `commit` calls explicit (`true`/`false`)
- [x] `./guide.sh`: A recv no longer prints `too old`, order includes
      the community branch (`2f0df65` day1, `11d0c7e` day7 appended)

## Out of scope: follow-up climb underflow (discovered 2026-07-24)

The reorder fix works. It made A's branch rich enough (an extra top
merge of Alice + community) to expose a SEPARATE pre-existing bug on
A's subsequent `sync send`:

```
ERROR : chain sync : sync.lua:302: attempt to concatenate a nil
value (local 'tip')
```

Root cause: in `meet` (`sync.lua:330-334`) `up = merge-base(left,
right)`, then `climb(G, com, up)`. When a nested merge's parent
merge-base falls BELOW the recv common ancestor `oct`, `climb` descends
past `com` to a root; `parents(root)` returns nil -> `climb(.., nil)`
-> concat nil at l.302.

Needs its own plan (e.g. `260724-climb-underflow.md`): make `climb`
stop when `cur` is an ancestor of `com` (or when `up` is at/below
`com`), instead of underflowing to a root.

## References

- [260723-consolidation-order.md](done/260723-consolidation-order.md)
- [2026-06-14-readme.md](2026-06-14-readme.md) — Hard Forks section
- [consensus.md](consensus.md) — fetch validation pipeline
