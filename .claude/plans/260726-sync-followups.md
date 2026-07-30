# Sync Follow-ups

Loose ends left by [260724-climb-underflow](done/260724-climb-underflow.md)
(nested-merge replay, hard-fork rule, causal freshness). None of them
blocked that work; each is independent of the others.

Ordered by how much they can bite.

## NEXT STEP (continue on another machine)

State as of 2026-07-29, branch `260724-climb-underflow`, at `fea41c8`
(`. review : sync : hardfork`), in sync with `origin`.

**The working tree is clean and nothing is half-applied.**
`reps.max` is back at `30*unit`; the `1000*unit` experiment lives in no
commit (the chat-sim measurements in section 7 were taken against a
scratch copy of `src`, not the worktree).

**`make tests` has NOT been run since `fea41c8`**, which carries both
the `--no-walk` bound and the `hardfork` restructure. That commit was
verified by hand instead:

- old vs new boundary logic over 20000 random orders: 0 mismatches
- `fork.time` axis via the ff path: refuses, receiver untouched
- `fork.posts` axis at exactly 100 entries: refuses, receiver untouched
- a young merge: still accepted (no false positive)
- nested merge: two peers derive identical orders

`tst/bug-err-kind.lua` passes; the rest of the suite has NOT been run
since it and the section-4 fix landed. Run `make tests` and `./guide.sh`
before starting anything new.

DONE so far: 0, 1, 4, 6, 7, Naming, cascade-voided peak.
OPEN, in this order: **2**, then 3 and 5 (those two need a design
decision -- see each section).

### Do this next -- section 2, a test that cannot fail

`tst/reorder-ancient.lua` drives its sync with `sync send`, so the
receiver runs inside the git pre-receive hook and `push` swallows its
stderr. The test only asserts that the command succeeded, so it stayed
green while the ancient post was being silently DROPPED.

Fix: drive it with a direct `sync recv`, or assert the resulting ORDER
instead of the exit status. Same trap applies to any test that pushes --
worth grepping `tst/` for other `sync send` cases while there.

Then **3** and **5**, both of which need a design decision (see each).

### Smaller loose ends, not worth their own section

- `README.md` has a bare `TODO: revert history` in the Hard Forks
  section. The documented recovery ("revert her local history, receive
  the settled branch, repost, send") was MEASURED to work, but there is
  no CLI for the revert -- today it means a raw `git reset --hard`
  inside the chain repo. Either add a command or say so in the text.
- The same section says a settled branch is one with 100 posts or 7
  days. True as the entrenchment condition, but only the PREFIX older
  than that window is frozen; the recent 100 posts / 7 days still
  reorder. As written it reads as if the whole branch were immutable,
  which contradicts the next paragraph.
- `hardfork`'s comment used to note that `order.lua` holds only
  post/like/revoke, so `merge`/`state` commits -- whose dates a pushing
  peer picks via `-o now` -- can never move the settled line. That is a
  security property of the rule and it is now written down nowhere.
- `tst/x.lua` is an untracked byte-identical copy of
  `tst/list-dag-roots.lua`. Leftover scratch; safe to delete.
- `luacheck` is not installed. It would have caught the use-before-
  declare that slipped into `hardfork` (Lua turns an undeclared local
  into a silent `nil` global), which silently disabled the `--no-walk`
  bound. Worth adding to the Makefile.

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

## 1. `list dag` crashes on TWO CONTENT ROOTS (DONE)

`make tests` green, including the new `tst/list-dag-roots.lua`.

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

Covered by `tst/list-dag-roots.lua`: RED before the fix (divide by
zero), green after. Wired into `make tests` after `cli-list.lua`.

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

Three fixes, all in the same branch (APPLIED):
- `siblings`: two nodes with EMPTY ups are siblings (they share the
  same absent up), so the roots land on one row instead of stacking
- column assignment: average only the ups that already HAVE a column,
  fall back to `MID` when none -- also covers `col[u]` being nil for an
  up ordered later, which would have been `arithmetic on nil`
- connector row: guard the fork branch on `col[u1]`, and drop a row in
  which no glyph was placed

Measured after the fix:

| topology                   | before             | after                    |
|----------------------------|--------------------|--------------------------|
| two content roots          | divide by zero     | `98389b3 0b86272` one row|
| `climb-underflow` (nested) | blank row + orphan | node + `(^a832477)`      |
| guide hub `#chat`          | --                 | byte-identical           |

`list order` is fine throughout, so this was the renderer only.

`list.lua:29` still warns the `dag` branch is AI-generated and
unreviewed. The read-through beyond these three fixes is NOT done.

Unblocks the README guide: the Hard Forks section can now show a
`list dag` of the forked state
(see [2026-06-14-readme](2026-06-14-readme.md)).

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

## 4. Unknown commit kind crashes the receiver (DONE)

`tst/bug-err-kind.lua`, wired into `make tests`, RED first then green.

A commit whose message carries no parseable `Freechains:` trailer left
`kind = nil`, and every branch below used it blindly. TWO reachable
crash sites, both fixed by one check upstream of them:

| site | needs | died as |
|-------------|--------------------------|----------------------------|
| `assert(kind=='state')` | only the bad trailer | `assertion failed!` |
| `"invalid "..kind` | bad trailer + forged sig | `concatenate a nil value` |

An earlier note in this plan named only the concatenation site. It is
reachable, but NOT what the forgery hits: adding a file passes the
create-mode check, so `kind` flows down to `assert(kind == 'state')`.

Fix: `KINDS = { post, like, revoke, state }` above `commit`, checked
immediately after the trailer is parsed and BEFORE anything uses `kind`:

```lua
if not (kind and KINDS[kind]) then
    error("invalid commit : invalid kind", 0)
end
```

`merge` is deliberately NOT in the set: those commits are built on a
detached head and discarded, so `main` never holds one. VERIFIED across
five repos built through nested merges, a 3h gap and a content conflict
(the path that writes `Freechains: merge`) -- every trailer reachable
from `main` was post/like/state, never merge.

Not a hole: the sync was refused before and is refused now. What changed
is the error surface -- and that surface is remote-visible. The hook
forwards the receiver's stderr to the pusher, so pre-fix anyone could
push a trailer-less commit and read back the receiver's absolute install
path:

```
remote: ERROR : chain sync : /usr/local/share/lua/5.4/freechains/chain/sync.lua:322: assertion failed!
```

Creating such a commit needs off-protocol writes, but only in the
ATTACKER's own repo -- the victim is an ordinary peer.

Note: the hook shells out to `freechains` from `PATH`, i.e. the INSTALLED
rock (`hooks/pre-receive`). The push path only gets this fix after a
reinstall; `sync recv` uses the worktree already.

### Trap hit while fixing it

A first attempt moved the signature check ABOVE the trailer parse. `kind`
was then an undeclared nil GLOBAL, so a commit with a valid trailer but a
signature that does not verify died as

```
attempt to concatenate a nil value (global 'kind')
```

-- reintroducing the same defect on a MORE reachable path (forging a
signature needs no trailer trick, just a tampered commit). Reproduced by
keeping a real `gpgsig` header and swapping the tree with `hash-object`.

Second undeclared-local bug of the session (see also section 6). Lua
turns them into silent nil globals; `luacheck` would catch both.

The forgery: write the trailer as the SUBJECT line rather than its own
paragraph. Freechains writes `(empty message)` as the subject and the
trailer after a blank line; with the trailer as the subject,
`%(trailers:key=Freechains)` returns nothing.

```
real   : "(empty message)\n\nFreechains: post\n"   -> kind = "post"
forged : "Freechains: post\n"                      -> kind = nil
```

Not a hole -- the sync is refused either way -- but the message must
name the problem instead of leaking a traceback.

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

## 6. Hard fork: bounded lookup + restructure (DONE)

`hardfork` read the WHOLE history to answer a question about at most
`fork.posts` entries:

```lua
git log --format='%H %at' <loc>     -- O(chain), every sync
```

The walk always stops at `n >= fork.posts`, so only the last 100 order
entries can ever be read. Now:

```lua
local low = math.max(1, #our-C.fork.posts+1)
local hs  = table.concat(our, " ", low, #our)   -- ranged concat, no temp table
git log --no-walk --format='%H %at' <hs>        -- fixed <=100 revs
```

Measured on an 881-commit repo: 11.9ms -> 6.6ms, of which ~3ms is
process spawn either way. The real point is the ceiling: the old form
scanned 200k+ commits on a 100k-post chain.

Restructured at the same time: the `n` counter is gone (`n >=
fork.posts` is exactly `i <= low`, and `low` already existed for the
range), the settled-boundary search is split from the prefix
comparison, and `ts[our[i]]` is asserted rather than guarded -- the
window provably covers every index the walk reaches, since the trigger
index IS the window's lower bound.

Verified: old vs new boundary over 20000 random orders (lengths 0-140,
deliberately NON-chronological times so the tip's time is not the
maximum and both axes fire) -- 0 mismatches.

### Careful: two traps hit while doing this

1. A first attempt put `local low` AFTER its use in `table.concat`.
   Lua reads the undeclared name as a nil GLOBAL, `table.concat` treats
   `i=nil` as `1`, and the bound silently vanished -- worse than before,
   because the whole order then goes on a command line and dies at
   `ARG_MAX` (2MB / 41 bytes = ~51k entries) instead of merely being
   slow. Tests stayed green: chains in `tst/` are tiny.
2. `assert` and the arithmetic run OUTSIDE any `pcall`, so a broken
   invariant surfaces as a raw Lua traceback, not
   `ERROR : chain sync : ...` -- same defect class as section 4.

### REJECTED: start the comparison at the shared prefix

The prefix comparison is O(chain) in the honest case (no mismatch => full
scan), so starting it at `#G_oct.order + 1` looks free. It is NOT sound.

The skip is safe only if `our[i] == their[i]` for every
`i <= #G_oct.order`. For `their` that holds: `climb` seeds `visited` from
`G_oct.order` and only appends, so new entries land AFTER that index.
For `our` it does not:

```
our order came from a PAST sync, with its own floor oct_past.
A merge inside loc's EXCLUSIVE region whose floor sat BELOW oct
(a branch forked long ago -- the nested-merge case) re-derived across
oct and reordered entries at indices <= #order(oct).
rem never saw that merge, so their order keeps oct's arrangement.
=> our and their disagree at i <= #G_oct.order, exactly where we skip.
```

A missed difference means a real reorder is silently ACCEPTED. Nested
merges are precisely where this breaks -- the topology this branch exists
to fix.

Do not resurrect this without a proof that covers `our`. An empirical
check on the ff scenario (`#oct=2`, first difference at index 3) confirms
one case and proves nothing about the general one.

### Done instead: scan the prefix backwards

`for i=set, 1, -1` rather than `1..set`. Verdict is identical (50000
random pairs, 0 mismatches); only the search order changes.

It is a BET, not a bound -- worst case is unchanged. Measured over a
1000-entry prefix, average comparisons before refusing:

| where the mismatch is        | forward | backward |
|------------------------------|---------|----------|
| last 10% (near the boundary) |     950 |       51 |
| uniform anywhere             |     500 |      501 |
| first 10% (ancient)          |      51 |      950 |

The bet is that contested history is RECENT history, which is the same
premise entrenchment itself rests on -- so the two are consistent.

## 7. `serial()` was quadratic (DONE)

Found while checking a report that the chat sim
(`/x/papers/26-06-vcs/sims/chat/chat-02.lua`) slows down badly as `N`
grows. It does, and the total is O(n^2):

```
msgs so far   50 -> 5.6s     1000 ->  9.0s
             500 -> 7.1s     1500 -> 12.3s     (seconds per 50 messages)
             800 -> 8.5s     1950 -> 14.8s
```

Attribution at 500 vs 2000 posts, per `post` command:

```
end-to-end      123 -> 245 ms
  git subprocs  119 -> 141 ms   flat-ish, NOT the cause
  Lua CPU        24 -> 144 ms   <- here
    serial()     11 ->  60 ms   <- super-linear
    dofile        4 ->  15 ms   linear
```

Cause: `serial()` accumulated with `out = out .. x` in a loop, copying
the whole string every iteration -- ~k^2/2 bytes of memcpy for a
k-entry table. `posts.lua` is 567KB at 2000 posts and is rewritten on
EVERY post, so one `write()` moved ~half a gigabyte.

Fix: accumulate into a table, `table.concat` at the end. Output is
byte-identical (checked against the old implementation on the real
567KB `posts.lua`, 118KB `order.lua`, `authors.lua`) -- which matters,
because these files are hashed into commits and compared between peers.

```
                       before    after
2200-line sim run      437.4s    364.3s
cost of last window /
  cost of first        2.24x     1.52x
per-50 at 1950 msgs    14.8s      9.9s   (-33%)
```

Residual growth (1.52x, not 1.0x) is structural, not a bug: every post
re-reads and rewrites the entire state and adds one tracked file, so
per-command work stays O(n) and the run stays O(n^2). Removing THAT
needs incremental state instead of a full rewrite per post -- a design
change, not a patch.

Two of my own measurements were wrong before this landed, both worth
remembering as method notes:

- `os.clock()` wrapped around `io.popen` measures nothing: child CPU is
  not counted, and it is not wall time. It made Lua look free (~1ms)
  when it was the whole problem.
- Timing `post` on a repo polluted by my own `git commit --allow-empty`
  probes measured FAILED runs: those probes carry today's date, the
  chain's peak jumped, and every 2010-dated post then died `too old`.

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
