# Climb Underflow: nested-merge replay + hard-fork rule

## Status: IN PROGRESS — working tree only, nothing committed

`main` untouched. Work so far (all uncommitted):

| file | change |
|------|--------|
| `sync.lua` | `climb` guards (`visited`, `ancestor`), `commit(..., false)` |
| `sync.lua` | `meet`: boundary-octopus ancestor + `hardfork` + `consensus` |
| `sync.lua` | `hardfork(rem, loc)` redesigned: span of `exc` (design #2) |
| `tst/climb-underflow.lua` | nested repro, deterministic tie-break |
| `tst/climb-underflow-gap.lua` | new: nested + 7-day gap, deterministic |
| `tst/fork-7-days.lua` | rewritten for design #2 (A posts ACROSS the window) |
| `Makefile` | both `climb-underflow*` wired in |

## The three defects fixed

1. UNDERFLOW: `meet` climbs each arm with its LOCAL fork `up` as floor;
   a nested inner merge forking deeper descends past a root ->
   `parents(nil)`. (A deeper global `com` does NOT help: `meet` re-floors
   at `up`. Verified: still crashes 3/3.)
2. DOUBLE-APPLY: the shared fork commit could be applied twice.
3. ASYMMETRIC DECISION: the replay must reproduce the sender's choice.
   It did not, because `meet` used a different ancestor (pairwise
   `merge-base` vs the sender's boundary octopus) AND skipped rule 1.

Principle: wherever two branches are compared, use the SAME ancestor and
the SAME rule.

## Hard-fork rule: design #2 (decided)

```lua
local function hardfork (rem, loc)      -- no common ancestor at all
    exc = git rev-list rem..loc         -- commits EXCLUSIVE to loc
    time  : newest(exc) - oldest(exc) >= C.fork.time
    posts : #posts(exc)               >= C.fork.posts
end
```

- **local**: every input is one of loc's own commits; `rem` only
  subtracts. A remote cannot inflate my entrenchment (this killed the
  `max(tips) - fork` idea: `apply()` bounds only PAST timestamps, so a
  remote could stamp year 3000 and force everyone to hard-fork).
- **deterministic**: timestamps are frozen in commits (no wall clock),
  so any peer replaying the merge re-derives the same verdict.
- **earned, not accrued**: entrenchment = SPAN of exclusive commits.
  Idling after a fork adds no independent history and must not buy
  entrenchment (old rule: fork -> idle 7d -> 1 post = entrenched).

Consequences accepted:
- 99 posts in a 6-day burst then total silence -> NOT entrenched
  (span 6d, posts 99). Any activity (post/like, or a recv that writes
  merge+state) extends the span, so only a fully offline branch freezes.
- `exc` counts all commit kinds and any author's commits sitting on my
  branch, not only my own posts.

## DECIDED: hard fork REFUSES the merge

Rule 1 no longer means "merge, but order myself first". An entrenched
local branch now rejects the sync outright:

```
ERROR : chain sync : hard fork
```

Consequences (all measured, `make tests` green):

- **No rule 1 inside `meet`.** No merge commit can encode a rule-1
  decision any more, so a replay only ever has to reproduce
  `consensus`. The section below is kept for the record — it explains
  why the inner call WAS needed under the merge-and-reorder design.
- **The refusal is one-directional.** The entrenched peer stops
  receiving; the other side (not entrenched) still absorbs its branch by
  plain consensus. So an entrenched peer keeps broadcasting but never
  listens, and since its span only grows, that is permanent.
- **Content partitions** instead of merely diverging in order. Under the
  old design both peers held every post and disagreed only on ordering.
- Fast-forwards are unaffected: `exc` is empty, so rule 1 cannot fire.
- Net code: -4 lines, and `hardfork` has a single call site.

Deferred: with the verdict no longer replayed, determinism is not
required, so the time axis COULD become wall-clock `now - oldest(exc)`
(simpler, fixes the "post once then idle" and "99 posts then idle"
blind spots). Not done because (a) `CMD.now` is what tests drive via
`--now`, and (b) on the push path the SENDER supplies `-o now=`, so a
remote could inflate the receiver's clock and force it to entrench.
Keeping the span rule for now.

## Why `hardfork` WAS also called inside `meet` (historical)

It is an outer local-vs-remote decision — but every merge commit IS a
past outer decision, frozen. A peer receiving an entrenched branch is
fast-forwarding (its own outer check never fires); to pass the strict
state check it must re-evaluate rule 1 AT that merge:
`hardfork(right, left)`, where `left` = the merger's local branch.

MEASURED (decisive test: A entrenched with LOWER reps beats B by rule 1,
then B replays A's merge):

| meet | replay of a hard-forked merge |
|------|-------------------------------|
| without `hardfork` | fff (3/3 mismatch) |
| with `hardfork`    | PPP |

Without it, any entrenched branch becomes unsyncable.

## Test flakiness (root-caused)

Commit hashes vary run to run (committer dates are not pinned). With
TIED reps, `consensus` falls to the hash tiebreak, so the expected order
is random and results are noise. All new/edited tests break the tie
deterministically with a pre-fork `KEY2 likes seed` (KEY1 > KEY2), like
`fork-7-days.lua` already did.

## NEXT STEPS (one at a time, pause between)

### Step 1 — fix the `err-post.lua` regression  [DONE]

RESOLVED: `climb` restored to `commit(G, cur, beg, true)`.
`false` was needed under the OLD algorithm (pairwise ancestor, no rule 1
in `meet`), which replayed commits out of chronological order. With the
octopus ancestor + rule 1 in `meet` the replay follows branch order, so
first-receipt validation can stay strict.

Verified 3/3 each: err-post too-old (correct error), reorder-ancient,
nested, gap, fork-7-days, hard-fork replay, simple fork.

Original report:

```
tst/err-post.lua:94  "B rejects post with old timestamp on sync"
  expected: ERROR : chain sync : invalid post : too old
  actual  : ERROR : chain sync : remote state mismatch
```

Cause: `climb` now calls `commit(G, cur, beg, false)`, disabling the
monotonic ("too old") guard on the FIRST-RECEIPT validation path. A
forged old-timestamp post is no longer rejected as invalid; it only
fails later, incidentally, via the state check. That is a validation
regression, not just a message change.

Hypothesis to test: restore `monotonic = true` in `climb`. It was set to
`false` earlier for the reorder-ancient case, but the surrounding
algorithm has changed a lot since (octopus ancestor in `meet`, rule 1 in
`meet`, design #2 `hardfork`), so `true` may now hold. Verify against:
err-post, reorder-ancient, climb-underflow, climb-underflow-gap,
fork-7-days, consensus, sync.

### Step 2 — run the FULL suite with the inner `hardfork` COMMENTED  [DONE]

CONFIRMED: with `meet` falling through to `consensus` only, the FULL
suite still passes. So no existing test forces a peer to replay a
hard-forked merge — the entrenched-branch replay path is uncovered.

(Related weakness found in Step 1: `tst/reorder-ancient.lua` uses
`sync send`, and the receiver runs inside the git hook whose stderr is
swallowed by `push`. With `monotonic=true` the ancient post is silently
DROPPED and that test still passes. It would be stronger as a direct
`sync recv`, or by asserting the resulting order rather than just
success.)

### Step 3 — test that FAILS without the inner `hardfork`  [DONE]

`fork-7-days.lua` extended: after A recvs B (A first by rule 1 despite
lower reps), B recvs A back and must re-derive the SAME order.

RED confirmed with `hardfork` commented (`fork-7-days.lua:125`):

```
ERROR : chain sync : invalid post : too old
B order: seed, like, beta        (a1, a2 LOST)
A order: seed, like, a1, a2, beta
```

Stronger than expected: without rule 1 in `meet`, B picks beta (higher
reps) first, so A's older a1 is applied after the clock passed a2 and is
rejected. An entrenched branch is not merely re-ordered — its posts are
DROPPED and the recv hard-fails.

### Step 4 — UNCOMMENT the inner `hardfork`  [DONE, pending full suite]

Uncommented; the replay step goes green (A == B, 5 entries).

### Then

- docs: `constants.lua` ("branch divergence limit"), `sync.md`,
  `consensus.md`, `time.md`, `threats.md`, README "Hard Forks"
- `./guide.sh` end to end
- commit; move plan to `done/`

## Checklist

- [x] Repro tests (nested + gap), deterministic
- [x] Diagnose: underflow + double-apply + asymmetric decision
- [x] `climb` guards; `meet` octopus ancestor + rule 1 + consensus
- [x] `hardfork` redesigned (design #2, span of `exc`)
- [x] `fork-7-days.lua` rewritten for design #2
- [x] Step 1: fix `err-post.lua` monotonic regression (climb -> true)
- [x] Step 2: full suite with inner `hardfork` commented -> ALL PASS
      (coverage gap confirmed)
- [x] Step 3: `fork-7-days.lua` replay step -> RED without inner `hardfork`
- [x] Step 4: uncommented; `make tests` FULLY GREEN
- [x] `./guide.sh` completes end to end
- [x] docs updated (constants, consensus.md, time.md, sync.md,
      threats.md, README)
- [x] `hardfork` simplified: ONE `git log --format=%at rem..loc`,
      all commit kinds count, `fork.posts = 2*100`
- [x] `make tests` green after the simplification
- [x] rule 1 REFUSES the merge; removed from `meet`; both fork tests
      reshaped (refusal + reverse direction); `make tests` green
- [x] docs for the refuse semantics: consensus.md, time.md, threats.md,
      sync.md
- [ ] README `### Hard Forks` + `guide.sh` rewrite (the guide currently
      demonstrates merge-and-reorder, so `./guide.sh` fails until then)
- [ ] move plan to `done/`

## Findings worth filing separately

- `tst/reorder-ancient.lua` uses `sync send`; the receiver runs in the
  git hook whose stderr `push` swallows, so a dropped ancient post still
  passes. Should use a direct `sync recv`, or assert the final order.
- `list dag` crashes on the nested topology:
  `list.lua:85: attempt to divide by zero` (renderer only, `list order`
  is fine).

## References

- [260724-reorder-ancient.md](done/260724-reorder-ancient.md) — exposed this
- [2026-06-14-readme.md](2026-06-14-readme.md) — Hard Forks section
- [sync.md](sync.md) — sync algorithm
