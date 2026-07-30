# TODO

- Open items left by done/260726-sync-followups.md
- Newest additions at top

# Idle chains are never entrenched

- Rule 1 measures the SPAN of my settled order
- The DAG records posts, not silence
    - post once, idle a year -> not entrenched
    - 99 posts in 6 days, then a month quiet -> not entrenched
- A peer with old-but-sparse history accepts any reordering

- Coverage gap, NOT a known exploit
    - entrenchment is local: each peer protects only itself
    - an active hub entrenches fine and stays protected
    - a quiet peer is unprotected, but is nobody's reference
    - do not build until a case is named where it matters

- Preferred fix: a `ping` commit kind
    - idle time needs an EVENT, or a clock
    - a ping manufactures the event
    - entrenchment stays derived from the DAG
    - `--now` keeps working, so tests and guide.sh still simulate time

- Ping design questions, worst first
    - whose pings count?
        - remote pings counting toward my span = denial-of-merge
        - a flood of pings would force me to entrench
        - count only MY OWN pings
    - in `order.lua` or not?
        - `hardfork` reads times via `ts[our[i]]` over order entries
        - a ping outside the order is invisible to it
        - a ping inside it inflates the `fork.posts` axis
        - likely split: time axis reads pings, count axis does not
    - free or paid?
        - must be free
        - else a peer out of reps can never protect itself
    - signed?
        - unsigned lets anyone inject
        - signed-but-free limits pings to members, rate limit per author
    - growth
        - every ping propagates and is replayed forever

- Won't do: wall-clock (`os.time()`)
    - `src/freechains.lua:213` is the ONLY clock read in the source
    - it is just the default of `CMD.now`, replaced by `--now`
    - a second, non-overridable read would break simulated time
- If ever done with a clock, use `CMD.now`, not `os.time()`
    - keeps the single time input
    - but it is SENDER-supplied on the push path
    - clamp it to the receiver's own peak + `time.diff`

# Entrenchment isolates honest absentees

- Recorded in threats.md T1
- Fires with no attacker
    - any peer away long enough crosses the threshold
    - then refuses to reconcile until it pulls first
- Availability cost may exceed the attack it prevents

- Options, none weighed yet
    - refuse only when the REMOTE is also entrenched
    - explicit `sync recv --force` that accepts the reorder
    - soften into the continuous decay in done/260723-fork-7day.md

# Done / dropped

- Lost security note in `hardfork`
    - DONE: recorded as threats.md T2d, not as a comment
    - a threat entry outlives a refactor of the function
- `reps.max` uncommitted
    - DROPPED: stale, tree and HEAD both `30*unit`
- `tst/sync.lua` drives with `sync send`
    - DROPPED: `send` IS the subject of steps 2, 4, 8
    - each asserts heads or beg refs afterwards
    - `ERROR` exits 1, the hook propagates, `push` exits 1
    - the only stderr `send` can swallow is the non-fatal
      loser-replay message, unreached on a fast-forward
- README: recovery has no CLI
    - DROPPED on request, still true
- README: settled-branch wording overstates
    - DROPPED on request, still true
- Add `luacheck`
    - DROPPED on request
