# Sync Follow-ups

Loose ends left by [260724-climb-underflow](done/260724-climb-underflow.md)
(nested-merge replay, hard-fork rule, causal freshness). None of them
blocked that work; each is independent of the others.

Ordered by how much they can bite.

## 0. Consensus baseline: pairwise merge-base (DONE)

`make tests` green (incl. the new test); `./guide.sh` refuses at `day 7`.

Reproduced first by `tst/hardfork-shared.lua` (2 peers, 2 keys, 4 posts):
an entrenched peer WRONGLY ACCEPTS a merge that reorders its settled
history, because a commit both peers already hold decides the consensus
between them. RED before the fix, green after; wired into `make tests`.

`consensus(G, com, a, b)` compared the branches from `oct`, the boundary
octopus, which sits DEEPER than the pairwise merge-base whenever an
unrelated earlier fork exists. Commits both peers already agree on then
fall inside BOTH `com..a` and `com..b`, and since reps are summed over
the SET of authors, such a shared commit hands its author's full reps to
whichever side lacked them.

Measured: same dispute, same reps, same authors -- outcome flips with an
unrelated earlier fork.

```
CASE 1  guide-like (an earlier unrelated fork exists)  -> ACCEPTED
CASE 2  identical, minus that earlier fork             -> hard fork
```

In CASE 1 Alice's own earlier post sits on the hub's branch, lending her
23 reps to the side she is arguing against; the hub wins and her post is
ordered last. That is why the guide's Hard Forks section had silently
stopped demonstrating anything.

Fix: keep `oct` for loading `G_oct` and as the climb floor, but compare
from `base(a, b)` = the pairwise merge-base, so the two ranges are
disjoint by construction and shared history never enters the comparison.
Two call sites: the top-level `fst, snd` and `meet`.

Minimal reproduction (`tst/hardfork-shared.lua`):

```
        seed[K1] -- like[K2]        <- oct lands HERE (one fork deeper)
                   /        \
              AW[K1]         cw[K2]    concurrent: the unrelated fork
                   \        /
                    MERGE             X absorbs AW (now shared)
                      |
                    d2[K2]            7 days later: X entrenched
                      |
   ALICE[K1]       (X tip)

from `oct` (wrong):  X: {K1,K2} vs A: {K1}  -> X wins, ALICE last, ACCEPTED
from AW   (correct): X: {K2}    vs A: {K1}  -> A wins, ALICE first, REFUSED
```

Result: CASE 1 and CASE 2 agree, and `guide.sh` refuses at `day 7`
again -- the `day 8` workaround (added while the exc-span rule was in
place) is reverted.

Knock-on: `tst/climb-underflow-gap.lua` reshaped. Its 7-day gap now
entrenches BOTH peers, so whichever would have its settled history
reordered refuses and nothing is replayed. The gap is now 3 hours --
still crossing the 1h freshness tolerance, still nesting two merges, but
below entrenchment. Rule 1 keeps its own tests (fork-7-days,
fork-100-posts).

### Step 2 (tested): the deep ancestor IS still needed

Tried dropping the octopus entirely. It fails, and so does each half:

| variant | comparison | `oct` (state) | `meet` floor | nested |
|---------|------------|---------------|--------------|--------|
| step 1  | pairwise   | octopus       | octopus      | PPP    |
| A       | pairwise   | octopus       | pairwise     | fff    |
| B       | pairwise   | pairwise      | octopus      | fff    |
| step 2  | pairwise   | pairwise      | pairwise     | fff    |

Failure is `remote state mismatch`, not a crash. In the nested case
`B recv A` is a FAST-FORWARD, so `merge-base` is B's OWN TIP: the replay
then starts from B's existing state and merely appends, keeping B's prior
arrangement instead of re-deriving the contested region. The deeper `oct`
forces the receiver to rebuild enough history to reproduce the sender's
order.

So the two ancestors answer different questions, and both are needed:

```
oct  (boundary octopus)  how much history to RE-DERIVE
                         deep: must rebuild the contested region
base (merge-base)        what each side CONTRIBUTED
                         shallow: disjoint, so shared commits never count
```

## 1. `list dag` crashes on TWO CONTENT ROOTS

```
lua5.4: src/freechains/chain/list.lua:86: attempt to divide by zero
```

Reproduced, and the trigger is NOT nested merges: it is any chain whose
first two content commits are concurrent. Clone a fresh chain before
anyone has posted, have both peers post once, sync:

```
genesis --+-- AW --+
          `-- CW --'-- M
```

`backs` walks THROUGH genesis, so both posts return an EMPTY set.
`siblings` (l.54) demands `#ua == 1`, so the second one opens its own
group, and the column midpoint divides by `#us == 0` (l.86).

Covered by `tst/list-dag-roots.lua` (RED until fixed).

The `tst/climb-underflow.lua` topology (AW / CW / M1 / takeover / M2)
does NOT crash -- measured. It renders, but emits a blank connector row
and an orphaned node, because the `groupOf[u] == g-1` filter (l.138)
matches nothing when a node's only up sits two groups above:

```
                 7fe7236
                            <- blank connector row
                 f6959f7
               (^62c021a)
```

Two fixes, both in the same branch:
- l.77-87: sum only ups that already have a column, fall back to `MID`
  when none -- also covers `col[u]` being nil for an up placed later
- l.54: two nodes with EMPTY ups are siblings (they share the same
  absent up), so the roots land on one row instead of stacking
- l.126-143: suppress the connector row when no glyph was placed

`list order` is fine throughout, so this is the renderer only.

`list.lua:29` already warns the `dag` branch is AI-generated and
unreviewed. Worth a read-through beyond the immediate division.

Also affects the README guide: the Hard Forks section cannot show a
`list dag` of the forked state while this stands.

## 2. `tst/reorder-ancient.lua` cannot fail

It drives the sync with `sync send`, so the receiver runs inside the git
pre-receive hook, whose stderr `push` swallows. During the work on
`monotonic` the ancient post was silently DROPPED and the test still
passed -- it only asserts the command succeeded.

Fix: drive it with a direct `sync recv`, or assert the resulting order
rather than the exit status. Same trap applies to any test that pushes.

## 3. Entrenchment cannot see idle time

The hard-fork rule measures the SPAN of my settled order. Nothing in the
DAG records that time passed while I was quiet, so:

- post once, idle a year -> not entrenched
- 99 posts in 6 days, then silence for a month -> not entrenched

A wall-clock rule (`now - oldest`) fixes both, and is now PERMISSIBLE:
since rule 1 refuses instead of merging, the verdict never enters a
merge commit and no peer ever replays it, so it need not be
deterministic.

Blocker: which clock.

| clock      | problem                                              |
|------------|------------------------------------------------------|
| `os.time()`| tests and `guide.sh` drive simulated time via `--now` |
| `CMD.now`  | on the push path the SENDER supplies `-o now=`, so a  |
|            | remote could inflate it and force a peer to entrench  |

So the prerequisite is that the receiver stops taking the sender's `now`
for this decision, which needs its own look: the hook currently relies on
that value to pin the dates of the commits it writes.

## 4. Unknown commit kind crashes the receiver

A commit whose message carries no parseable `Freechains:` trailer leaves
`kind = nil` in `commit` (sync.lua), which then reaches the mode check
and dies on a concatenation:

```
ERROR : chain sync : src/freechains/chain/sync.lua:218: attempt to concatenate a nil value (local 'kind')
```

Found while hand-forging a state commit: writing the trailer as the
SUBJECT line (rather than its own paragraph, after the literal
`(empty message)` subject freechains writes) makes git's trailer parser
return nothing.

Not a hole -- the sync is refused either way -- but the message violates
the project's `ERROR : <command> : <detail>` format. `kind` should be
validated right after it is parsed, against the known set
(`post`/`like`/`revoke`/`state`), with a proper
`invalid commit : unknown kind` error.

## 5. Entrenchment isolates honest absentees

Recorded in [threats.md](threats.md) T1. The refusal fires with no
attacker: any peer away long enough crosses the threshold and then
refuses to reconcile until it pulls first. The availability cost to
honest absentees is arguably larger than the attack it prevents.

Options not yet weighed:
- refuse only when the REMOTE is also entrenched (mutual deadlock only)
- an explicit override (`sync recv --force`) that accepts the reorder
- soften rule 1 into the continuous decay already sketched in
  260723-fork-7day.md

## Naming (done)

The causal high-water now reads as one concept in three forms:

| name         | meaning                                            |
|--------------|----------------------------------------------------|
| `TIME(h)`    | the commit's OWN author date                       |
| `PEAK(h)`    | the peak RECORDED in its tree (`state/now.lua`)    |
| `PEAKS(hs)`  | the peak COMPUTED over a set of commits            |
| `G.now`      | the live accumulator during replay                 |

Was `NOW` / `STORED_NOW` / `max_ancestor_time`. `NOW` misled: the value
is a past commit's stamp, never "now". `PEAKS` is not "max peak" twice
over: it is the max among the commits' peaks AND their own times.

`ANCS(h)` was a fourth form -- `PEAKS` over `h`'s parents -- but it
mixed the DAG walk into the time group. Split: the walk is now
`parents(h)` (pure topology, no time), and every call site folds it
explicitly as `PEAKS(parents(h))`. Three sites: `apply` (freshness),
`sync.lua` `commit` (verify a `state` commit), `sync.lua` case 3
(rewrite `G_rem.now`).

`common.lua` now groups as: `trailer` / `parents` / `backs` (DAG), then
`TIME` / `PEAK` / `PEAKS` (time).

Two duplicate walks collapsed onto `parents`:

- `backs(h)` -- post/like/revoke ancestors -- is exactly `parents`
  recursed through `state`/`merge`; it had its own inlined `rev-list`
  and a `me` flag to drop the commit itself.
- `sync.lua`'s local `parents(tip)` in the replay block was a third
  copy; `climb` now unpacks the global (`assert(#ps <= 2)`).

`backs` KEEPS its name: it is the user-facing edge, printed as the
`backs` field by `chain get` and drawn by `chain list dag`. `parents` is
the git plumbing underneath it.

`make tests` green; `./guide.sh` unchanged end to end (hub still refuses
at `Alice takes over`).

Still open: `backs`'s `see` guards RESULTS only, not the `state`/`merge`
recursion, so a diamond of plumbing commits is walked more than once.

## Cascade-voided times leaked into the stored peak (FIXED)

`make tests` caught it -- `consensus.lua` test 3, "loser invalidated by
winner context", at the final `B recvs from A`:

```
ERROR : chain sync : invalid state : now
```

The writer stored `G.now`, the replay accumulator. A commit VOIDED by a
cascade advances that accumulator and is then dropped from the DAG, so
the recorded value stopped being derivable from history -- and the
verifier, correctly, refused it:

```
merge  t=3000  peak=2100      <- P2's time; P2 was voided
  |- state t=2000 peak=2000
  `- post  t=2000 peak=0      -> ANCS = 2000
```

Fix: the stored peak is DERIVED from the parents of the commit about to
be created (`PEAKS{"HEAD","MERGE_HEAD"}`), never from `G.now`, so writer
and verifier share one formula. The verifier's inlined loop collapsed to
`ANCS(hash)`.

Side effect: a merge now records the peak of its parents rather than the
`--now` the sync was invoked with (1100, not 1150). That is the point --
the value has to be reproducible by every peer that replays the merge,
and no peer knows the receiver's clock.

Both `TIME` and `PEAK` are needed, and not interchangeably:

- `sync.lua` verifies a `state` commit against its parents, and a parent
  is normally a POST, whose tree still holds the previous peak. Drop
  `TIME` there and every honest sync fails `invalid state : now`
  (measured).
- `common.lua` checks freshness for post/like commits only, whose parent
  is always a `state` commit (already current), so `TIME` is redundant
  there today -- kept as the guard if a stale-state commit ever becomes
  a parent.

## Not doing (recorded, decided)

- Ordering entries by `(time, hash)` instead of consensus: discards
  reps-consensus. Rejected.
- `max(loc, rem)` timestamps for entrenchment: remote-controlled, so a
  peer could force everyone to fork. Rejected.
- Deep/global common ancestor for `climb`: `meet` re-floors at its own
  `up`, so it does not remove the guards, and it breaks `hardfork`.
  Rejected (measured).

## References

- [done/260724-climb-underflow.md](done/260724-climb-underflow.md)
- [threats.md](threats.md) — T1, T1a, T1b, T2a
- [time.md](time.md) — the time rules and their windows
- [consensus.md](consensus.md) — hard fork rule, settled prefix
