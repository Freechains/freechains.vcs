# TODO

- Open items left by done/260726-sync-followups.md
- Newest additions at top of each section

# Open

## `--now` does not traverse clone/push

- `chains add clone` re-execs `sync recv` WITHOUT `--now`
    - a clone at simulated time validates on the real clock
    - fix: forward `--now=ARGS.now` in the re-exec (one line)

## Sandbox `STATE.read` too (T6c leftover)

- `state.lua` `M.read` still does `load(src)()`, with globals
- Safe TODAY, and the reasons are worth keeping
    - the blob is our own `serial(G)`: literals only
    - `refs/states/*` are never fetched: every refspec is
      explicit (`main`, `refs/begs/*`, `refs/payloads/*`)
    - nor pushed: `hooks/pre-receive` rejects any other ref
- So reaching it means owning `~/.freechains/` already
- Still worth one line, as defense-in-depth
    - the guarantee rests on that hook being present and
      correct in EVERY repo
    - a hub with no hook accepts a pushed `refs/states/<cid>`,
      and the unsandboxed `load` turns a forgery into code
- Fix: `load(src, "=state", "t", {})`, as T6c did elsewhere
- Check: no snapshot may rely on a global (`serial` says none can)

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

## Perf cleanups P1 (profile first, land measured)

- From done/280808-redesign.md "Small cleanups"; correctness
  is unaffected, so gated on something actually being slow
- P1: `hardfork` one `cat-file blob` per window entry ->
  one `cat-file --batch`

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

## Guide: settled-branch wording overstates

- `doc/guide.md:511`, not README
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

## `sync send --now` (push-option `-o now=`)

- decided won't-do in done/260721-send-now.md
- the hook validates on the receiver's own clock, by design

## Perf P2-P4 (aid memos, cid<->aid index)

- `aid` dissolved in done/260821-cid-aid-tree.md
- nothing left to memoize; P1 stands alone
