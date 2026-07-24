# Climb Underflow -> Canonical Consensus Fold

## Status: FIX COMMITTED — pending `make tests` + `./guide.sh`

Branch `260724-climb-underflow`, pushed to origin. The code fix
(`sync.lua` derive fold, `tst/climb-underflow.lua`, `Makefile`) is
COMMITTED and PUSHED. On another machine:
`git checkout 260724-climb-underflow && git pull`. Not yet run: the full
suite and the guide. START AT "## NEXT STEP".

## Symptom

`sync recv`/`send` of a branch with NESTED merges crashed the receiver:

```
ERROR : chain sync : sync.lua:300: attempt to concatenate a nil value (local 'tip')
```

Then, once the crash was patched, it failed the strict state check:

```
ERROR : chain sync : remote state mismatch
```

Surfaced in `guide.sh` final step (A's `sync send` back to hub X).

## Root cause (two coupled bugs)

1. UNDERFLOW: `meet(com, left, right)` recursed `climb(up, side)` using
   its LOCAL fork `up` as the floor. A nested inner merge forking DEEPER
   than `up` made `climb(up, up')` with `up' < up` descend past a root ->
   `parents(nil)`.
2. ORDER: even patched, the merged order was NOT a pure function of the
   DAG. Sender stored via the reorder-append path; receiver re-derived
   via `climb`; the two broke the CW/AW tie differently -> byte mismatch.
   (Diff was purely `order.lua`; reps identical.)

Both stem from `climb`/`meet` assuming every merge fork is >= the
segment floor and no commit is visited twice — nested re-merges break
both. Deepening `oct` does NOT help (meet still recurses on local `up`).
A `(time,hash)` sort was REJECTED (discards reps-consensus).

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
The test asserts B's order contains `takeover` (red before fix, green
after).

## Solution: one canonical `derive` fold, used by store AND check

A canonical order provably EXISTS (B, A, H-community all agreed via
non-underflowing paths). The fold that reproduces it, PROTOTYPE-VALIDATED
(nested == canonical; simple fork == existing algo, byte-for-byte):

```
derive(loc, rem):
  Gd = state at genesis ROOT; visited = Gd.order
  for M in `rev-list --topo-order --reverse --merges loc rem`:  -- ancestors first
      p1,p2 = parents(M); fork = merge-base(p1,p2)
      emit(fork); w,l = consensus(Gd, fork, p1, p2); emit(w); emit(l)
  emit(merge-base(loc,rem)); emit(fst); emit(snd)   -- top split: fst wins
  emit(h): if visited[h] return; emit(p1); emit(p2); visited[h]=true; commit(Gd,h,nil,false)
```

Why it fixes both: deepest-fork-first => no underflow AND siblings
ordered together at their true fork; `visited` => no double-apply;
`consensus()` unchanged => reps-consensus preserved; same function for
sender store + receiver check => can't diverge.

## Changes ALREADY made (working tree)

| file | place | change |
|------|-------|--------|
| `src/freechains/chain/sync.lua` | recv derivation block (was `climb`/`meet`, ~l.295) | replaced with the `derive` fold producing `G_rem` = canonical merged state |
| `src/freechains/chain/sync.lua` | divergent final-state block (~l.404) | dropped `G_fst` state-building; git-merge loop now only shapes the DAG + detects content conflicts; iterates loser commits in `G_rem.order` |
| `src/freechains/chain/sync.lua` | final state write (~l.512) | `write(G_fst)` -> `write(G_rem)` |
| `src/freechains/chain/sync.lua` | doc comment (~l.46) | `climb / meet` -> `derive` |
| `Makefile` | `tests:` target | added `$(L) climb-underflow.lua` |

Scratch smoke (all passed): nested fixed (B order == A order); simple
fork diverge+converge (A==B SAME); hard-fork 7-day local-first
preserved; likes/reps ok. `luac5.4 -p` clean; no stale `G_fst`/`climb`/
`meet` refs.

## NEXT STEP (start here on the other machine)

1. `git checkout 260724-climb-underflow && git pull` (the code fix is
   already committed/pushed; verify with `git log --oneline -5`).
2. RUN: `make tests`
   - MUST be fully green, especially `consensus`, `fork-7-days`,
     `fork-100-posts`, `reorder-ancient`, and the new `climb-underflow`.
   - If `consensus`/`fork-*` regress: the top-level split `emit(fst);
     emit(snd)` or the hard-fork winner choice is off — compare a failing
     case's `order.lua` against a pre-change checkout.
   - If a state mismatch reappears: dump the derived vs committed
     `order.lua`/`posts.lua` diff (see prior technique: patch the
     mismatch branch to print `git diff HEAD -- .freechains/state/`).
3. RUN: `./guide.sh` — must complete past the old `sync.lua:300` crash;
   A's final `sync send` should succeed and X's `list order` print the
   full merged order.
4. If both green: mark checklist done, move this plan to
   `.claude/plans/done/`.

## Known follow-ups (not blockers)

- EFFICIENCY: `derive` re-derives from the genesis ROOT every recv
  (O(history) git calls). Correctness-first was the deliberate choice.
  Optimize later by seeding from a deep `oct` whose committed order is a
  canonical prefix (oct = deepest fork in region).
- CONTENT CONFLICTS: the git-merge loop can partial-merge on a real
  content conflict while `G_rem` accounts for all commits; tests use
  distinct files so this is untested. Revisit if same-file edits matter.

## Checklist

- [x] Repro test (red) — minimized to 2 peers / 3 posts
- [x] Diagnose: nested-merge underflow + oct-dependent ordering
- [x] Design + prototype the canonical `derive` fold (validated)
- [x] Implement in `sync.lua` (derive fold; divergent stores `G_rem`)
- [x] `climb-underflow.lua` wired into `make tests`
- [x] Scratch smoke: nested fixed; simple/hard-fork/likes intact
- [ ] `make tests` green  <-- NEXT
- [ ] `./guide.sh` completes end to end
- [ ] move plan to `done/`

## References

- [260724-reorder-ancient.md](done/260724-reorder-ancient.md) — the fix
  that exposed this (A's branch gained the deep merge)
- [2026-06-14-readme.md](2026-06-14-readme.md) — Hard Forks section
- [sync.md](sync.md) — sync algorithm
