# TODO

- Open items left by done/260726-sync-followups.md
- Newest additions at top of each section

# Open

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

## README: recovery has no CLI

- Hard Forks section carries a bare `TODO: revert history`
- The documented recovery was MEASURED to work
    - revert local history, recv the settled branch, repost, send
    - a plain recv+send does NOT work
    - consensus re-inserts the post inside the frozen prefix
- But there is no command for the revert
    - today it is a raw `git reset --hard` in the chain repo
- Either add a command or say so in the text

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
