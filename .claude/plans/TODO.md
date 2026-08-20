# TODO

- Open items left by done/260726-sync-followups.md
- Newest additions at top of each section

# Open

## Dictators field: keys with infinite reps

- a per-chain `dictators` field listing public keys
- listed keys have infinite reps
    - never spend, never mature, never run out
    - likes/dislikes from them always apply
- open: where stored? genesis field vs config
- open: can dictators be added/removed after genesis?

## Per-chain configurable constants

- move `constants.lua` values into a per-chain file
- each chain picks its own reps/time parameters
- ANSWERED: genesis, but only for what replay reads
    - the test is whether a value derives `G`
    - divergent values across peers = divergent replay

### Genesis (consensual, immutable)

- `time.half`, `time.full`: discount and consolidation
- `reps.cost`, `earn`, `revoke`, `max`: every balance
- `vote.tax`, `vote.split`: every transfer
- all flow through `apply`/`advance` into the state blob

### Config (local policy, never replayed)

- `fork.time`, `fork.actions`: entrenchment is self-protection
- the verdict is never replayed: no merge commit encodes it
- in genesis, a chain author could disable everyone's rule 1

### Straddles both: `time.diff`

- `too old` is DAG-derived and replayed -> genesis
- `too new` reads MY clock -> config
- likely two values, not one

### Open

- validate genesis constants on clone
    - hostile `reps.cost = 0` or `vote.tax = 100`
    - bounds per field, or a whole-table sanity check
- what happens when `version` and the constants disagree?

## Perf cleanups P1-P4 (profile first, land measured)

- From done/280808-redesign.md "Small cleanups"; correctness
  is unaffected, so gated on something actually being slow
- P1: `hardfork` one `cat-file blob` per window entry ->
  one `cat-file --batch`
- P2: memoize `ACTION.aid(cid)` (diff-tree per call;
  `commit()` and `GIT.time` both shell it per cid)
- P3: more memos, same shape as GIT.parents/time
    - `ssh.pub.commit(cid)`: consensus ranges overlap on
      nested merges
    - snapshot `now`: `peaks` parses WHOLE G per edge ->
      number-only cache
    - TRAP: `STATE.read` itself must NOT be memoized
      (callers mutate the returned table)
- P4: batch in-process index (P2+P3 unification)
    - ONE `git log --format=%H --diff-filter=A --name-only`
      over the region -> cid<->aid map, one shell
    - restores replay's visited seeding:
      `visited[a2c[aid]]` for aid in the replayed G's order
    - fences: aid->cid NOT 1:1 across branches (dup-skip
      stays); seed ONLY from the replayed G's own order,
      NEVER from `STATE.has` (refused syncs also snapshot)
    - also: memo `ancestor()` per (cur, floor); mark
      ancestor-true cids visited in the OUTERMOST climb only

## Hard-prune plan is stale on rule 1

- `260723-hard-prune.md` predates the refuse-semantics rule 1
- Written against `hardfork(oct, loc)`: entrenched branch WON
- Now it REFUSES, so no merge and no checkpoint forms
- Its Goal anchors the graft on that checkpoint
- Noted in the plan (`## STALE`), not yet fixed
- Fix: drop the hardfork trigger, keep `c1` time/count driven

- Also recorded there, both new:
    - `## MEASURED`: Track A reclaims metadata only
        - blobs ride forward in `c1`'s tree, clone gets them all
        - provenance is lost, content is not
    - fold list was incomplete: `kind`, vote table, filename
        - `time`/`sign` already stored but still re-derived

## Idle chains are never entrenched

### Problem

- Rule 1 measures the SPAN of my settled order
- The DAG records posts, not silence
    - post once, idle a year -> not entrenched
    - 99 posts in 6 days, then a month quiet -> not entrenched
- A peer with old-but-sparse history accepts any reordering

### Scope

- Coverage gap, NOT a known exploit
    - entrenchment is local: each peer protects only itself
    - an active hub entrenches fine and stays protected
    - a quiet peer is unprotected, but is nobody's reference
    - do not build until a case is named where it matters

### Preferred fix: a `ping` commit kind

- Idle time needs an EVENT, or a clock
- A ping manufactures the event
- Entrenchment stays derived from the DAG
- `--now` keeps working, so tests and guide.sh still simulate time

### Design questions, worst first

- Whose pings count?
    - remote pings counting toward my span = denial-of-merge
    - a flood of pings would force me to entrench
    - count only MY OWN pings
- In `order.lua` or not?
    - `hardfork` reads times via `ts[our[i]]` over order entries
    - a ping outside the order is invisible to it
    - a ping inside it inflates the `fork.posts` axis
    - likely split: time axis reads pings, count axis does not
- Free or paid?
    - must be free
    - else a peer out of reps can never protect itself
- Signed?
    - unsigned lets anyone inject
    - signed-but-free limits pings to members, rate limit per author
- Growth?
    - every ping propagates and is replayed forever

### Rejected: wall-clock (`os.time()`)

- `src/freechains.lua:213` is the ONLY clock read in the source
- It is just the default of `CMD.now`, replaced by `--now`
- A second, non-overridable read would break simulated time
- If ever done with a clock, use `CMD.now`, not `os.time()`
    - keeps the single time input
    - but it is SENDER-supplied on the push path
    - clamp it to the receiver's own peak + `time.diff`

## Entrenchment isolates honest absentees

### Problem

- Recorded in threats.md T1
- Fires with no attacker
    - any peer away long enough crosses the threshold
    - then refuses to reconcile until it pulls first
- Availability cost may exceed the attack it prevents

### Options, none weighed yet

- Refuse only when the REMOTE is also entrenched
- Explicit `sync recv --force` that accepts the reorder
- Soften into the continuous decay in done/260723-fork-7day.md

# To Re-Check

- Dropped earlier, each verdict to be revisited from scratch

## README: settled-branch wording overstates

- Says a settled branch has 100 posts or 7 days
- True as the entrenchment CONDITION
- Only the prefix OLDER than that window is frozen
- The recent 100 posts / 7 days still reorder
- As written it reads as if the whole branch were immutable
    - contradicts the next paragraph

## Add `luacheck`

- Not installed
- Would have caught two undeclared-local bugs in one session
    - `low` used before its declaration silently disabled the
      `--no-walk` bound
    - `kind` used before its declaration crashed on forged signatures
- Lua turns an undeclared local into a silent nil global
- Worth a Makefile target

<!-- ------------------------------ WON'T DO ------------------------------ -->
