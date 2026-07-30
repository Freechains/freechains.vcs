# Climb Underflow: nested-merge replay + hard-fork rule

## Status: DONE — `make tests` and `./guide.sh` green

Everything below is implemented in the working tree (nothing committed by
me). Three separate defects were fixed on the way; the last one turned
out to pre-exist on `main`.

| area          | change                                          |
|---------------|-------------------------------------------------|
| `sync.lua`    | `climb` guards: nested-merge underflow           |
| `sync.lua`    | `meet` uses the boundary-octopus ancestor        |
| `sync.lua`    | rule 1 REFUSES; gone from `meet`; order-based    |
| `common.lua`  | `max_ancestor_time`; `monotonic` removed         |
| `constants`   | `fork.posts = 100` (the order counts messages)   |
| tests         | +climb-underflow{,-gap}, +consensus-gap;         |
|               | reshaped fork-7-days, fork-100-posts, reorder-*  |
| docs          | consensus/time/sync/threats.md, README, guide.sh |

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

## NEXT DESIGN: entrenchment protects the ORDER, not the commit set

### Why the current `exc` measure fails

`hardfork(rem, loc)` measures `exc = git rev-list rem..loc`. When my tip
is an ANCESTOR of `rem` (the remote absorbed my branch), `exc` is EMPTY —
so the check reads "nothing of mine is at stake" exactly when everything
of mine is being reordered:

```
        hello                     A pulls X, then pushes back:
          |
         like                     mine  : hello like b1    b2
        /     \                   theirs: hello like ALICE b1  b2
   b1 (day 1)  ALICE                                ^ spliced into settled
      |          \                                    history
   b2 (day 9)     \
        \         /               exc = rev-list A..X = {}  -> not entrenched
         M = merge                -> X merges -> only an accidental
   [X tip inside A's history]        "invalid post : too old" stops it
```

So pull-then-push bypasses rule 1 by construction.

### The rule

Compute a FROZEN LINE from my own order: walk back from my tip until the
walked part spans `fork.time` or reaches `fork.posts` entries; everything
before that point is settled.

```
my order:  hello  like  b1     b2      c1      c2
time:      d0     d0    d1     d9      d9.5    d9.9   <- tip
           |__ FROZEN __|      |____ fresh (within 7d) ____|
                        k=3
```

Then: the CANDIDATE result of this sync must preserve `mine[1..k]`
verbatim, or it is a hard fork.

- ff case: the candidate is the remote's committed order.
- divergent case: the candidate is the order I would compute. So the
  check runs AFTER deriving it and BEFORE writing anything -- a later
  call site than today's.

### What it fixes

| incoming                        | today (`exc`) | frozen line |
|---------------------------------|---------------|-------------|
| rewrites my settled history     | refuse        | refuse      |
| pull-then-push (my tip absorbed)| ACCEPT (bug)  | refuse      |
| appends after my history        | REFUSE (bad)  | accept      |
| reorders only fresh posts       | refuse (bad)  | accept      |

The 3rd and 4th rows are the over-rejection: today an entrenched peer
drops content that never threatened its order. That is the same cost
noted in threats.md T1 (honest absentees isolate themselves).

### Bonus: removes a `-o now` exposure

`sync send` forwards `-o now=` and the receiving hook turns it into
`--now=`, so the SENDER picks the timestamps of the `merge`/`state`
commits the RECEIVER writes into its own branch. With the span counting
all commit kinds, a push carrying a far-future `now` would leave the
receiver's own branch spanning centuries -> permanently entrenched ->
refuses everyone. (`apply()` bounds only PAST timestamps.)

`order.lua` holds only `post`/`like`/`revoke`, so a frozen line computed
from the order is immune to this: nothing the sender stamps on my
bookkeeping commits can move it. Residual exposure is author-chosen post
timestamps, already catalogued as T2b.

`-o now` itself stays (tests and `guide.sh` need simulated time), it just
stops feeding a security decision.

### Knock-on

- `fork.posts` returns to `100` (the order holds messages, not commits).
- The remote's order is a CLAIM at check time; safe, because a state that
  does not match its own DAG is rejected by the strict state check
  moments later. Worth a code comment.

## FIXED: consensus reorder produced an unvalidatable state

PRE-EXISTING on `main` (verified by re-running against
`git show main:src/freechains/chain/sync.lua`). Not introduced here.
NOT specific to hard forks, and NOT rare.

### Reproduction (3 peers, nothing entrenched)

```
seed, like             -- shared; K1 > K2
B posts "low"  @t      -- low reps
A posts "high" @t+2h   -- high reps, 2 HOURS later

A recv B  -> accepted.  A's order: seed like HIGH low
                        (winner is NEWER, so it is ordered FIRST)
C recv A  -> ERROR : chain sync : invalid post : too old
             C keeps only [seed, like]
```

Any consensus merge whose winner posted more than `C.time.diff` (1h)
after the loser produces a state that OTHER peers cannot validate. Two
peers posting an hour apart is ordinary, so such merges simply do not
propagate.

### Diagnosis

`apply()` guards freshness against the RUNNING state:

```
if time < G.now - C.time.diff then return false, "too old" end
```

That assumes commits arrive in chronological order. A consensus replay
applies them in CONSENSUS order, so an older loser commit legitimately
follows a newer winner commit and trips the guard.

The sender does not notice: its divergent path applies loser commits
with `monotonic=false`. The replay (`climb`) uses `true`, so every
receiver rejects what the sender happily committed.

### Why the earlier "option 2" does not work

The idea was to enforce the guard only for commits NEW to this peer.
In the reproduction C has never seen either post -- both are new -- so
the guard still fires. Being new is not the distinction; ORDER is.

### Fix: causal high-water rule (decided)

The guard must not depend on how the replay walks the DAG. Compare each
commit against the high-water mark of its ANCESTORS, computed
structurally:

```
hw(c)    = max( time(c), max hw(p) for p in parents(c) )   -- memoised
valid(c) <=> time(c) >= max( hw(p) for p in parents(c) ) - C.time.diff
```

This is exactly the old `G.now` semantics (`G.now` IS the max time seen)
but derived from the DAG instead of from the replay's running state.

Why not the simpler variants:

| variant                     | skew    | cumulative | order-dep |
|-----------------------------|---------|------------|-----------|
| old: `>= G.now - diff`      | ok      | bounded    | YES (bug) |
| strict parent: `>= parent`  | REJECTS | n/a        | no        |
| parent+tol: `>= parent-diff`| ok      | UNBOUNDED  | no        |
| hw(ancestors) - diff        | ok      | bounded    | no        |

`C.time.diff` (1h) is kept, attached to the ancestor high-water mark.

Checked against every case we have:

| case                                  | verdict                       |
|---------------------------------------|-------------------------------|
| consensus-gap: low@1300, hw(anc)=1200 | accepted, any apply order     |
| err-post: forged@1970, parent@11000   | rejected ("too old")          |
| reorder-ancient: beta@2000, tip@10000 | vs beta's OWN ancestors -> ok |
| honest peer 30 min behind             | inside the 1h tolerance       |

Knock-on: `monotonic` disappears from `apply()` and `commit()` (the
check no longer depends on apply order), and the `G.now - diff` guard
goes with it. Local posting rejects `--now` behind HEAD; the auto
`merge`/`state` commits a recv writes are clamped to
`max(CMD.now, parents)` so they cannot be born invalid.

That clamping also makes `-o now` unnecessary for CORRECTNESS: it stays
only so tests and `guide.sh` have reproducible timestamps.

Accepted loss: `apply()`'s running-state guard was the only thing
rejecting a post dated well below the chain's progress on a branch whose
own ancestors are old. That is T2a (backdating on offline branches),
already documented as accepted, and `time.md` already names the
monotonic parent rule as the intended bound.

### Resolution

`tst/consensus-gap.lua` (3 peers, no hard fork) reproduced it, then:

- `apply()` computes `max_ancestor_time(T.hash)` itself -- `hash^@` is
  exactly the parents' reachable set, so ONE git call, no recursion and
  no memo -- and rejects `time < that - C.time.diff`.
- `monotonic` is gone from `apply()`, `commit()` and every call site:
  the check no longer depends on apply order, so no caller needs to
  say which mode it wants.
- Local posting is covered by the same rule (HEAD is the parent), which
  closed a gap where a backdated local post was accepted locally and
  then rejected by every peer.

`make tests` and `./guide.sh` both green.

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
- [x] `guide.sh` Hard Forks rewritten: community posts `day 1`..`day 8`
      (span >= 7d -> hub entrenched), Alice returns and her `sync send` is
      REFUSED. Verified: `remote: ERROR : chain sync : hard fork` +
      `! [remote rejected]`. Alice's recv dropped (not needed)
- [x] README `### Hard Forks` rewritten around the real output
- [x] FROZEN LINE rule implemented (order-based entrenchment):
      pull-then-push REFUSED, append-after ACCEPTED, fresh reorder
      ACCEPTED, original divergence REFUSED
- [x] `fork.posts` 2*100 -> 100 (the order counts messages)
- [x] docs realigned (constants, consensus.md, README)
- [x] `make tests` green
- [x] consensus-reorder bug: `tst/consensus-gap.lua` + causal freshness
      via `max_ancestor_time`; `monotonic` removed everywhere
- [x] `make tests` green (incl. `consensus-gap`)
- [x] `./guide.sh` green
- [x] move plan to `done/` (follow-ups moved to 260726-sync-followups.md)

NOTE: the old guide silently stopped demonstrating anything under the span
rule — A's single post spans 0, so no fork occurred and both orders were
identical while the text still claimed they diverged. The `day 7` -> `day 8`
change is what actually crosses the 7-day span.

## Guard coverage: `ancestor(cur, com)` (added later)

The two repro tests only exercise `visited`: commenting
`ancestor(cur, com)` out of `climb` leaves the whole suite GREEN.

`visited` cannot replace it. Random-DAG search (real merges only:
neither parent an ancestor of the other) finds shapes where an inner
boundary octopus `up` lands STRICTLY BELOW the floor `com`, on a commit
held in no `order` — genesis or a `state` commit:

- a criss-cross merge below the fork point makes the region between the
  outer merge's parents attach to shared history at TWO points
- so its `octopus` drops to the deeper one, past `com`
- `cur == com` never matches and `visited` never holds it, so the climb
  descends to a root: `parents()` empty -> nil hash in a git command

- [x] `tst/bug-climb-ancestor.lua`: 4 peers, criss-cross `M0`, stale
      peer C posting below it; `com` = `S2`, `up` = genesis
- [ ] confirm RED with the guard commented, GREEN with it restored

## Follow-ups

Moved to [260726-sync-followups.md](../260726-sync-followups.md).

## References

- [260724-reorder-ancient.md](done/260724-reorder-ancient.md) — exposed this
- [2026-06-14-readme.md](2026-06-14-readme.md) — Hard Forks section
- [sync.md](sync.md) — sync algorithm
