# 260817-storage

- source: done/280808-redesign.md, sections "S6" and E stage 2
- theme: what bytes live where, and when they die
- order revised 26/08/18 after measuring: E stage 2 first,
  S6.1 postponed, the refspec cliff split out as S6.0

# Measured 26/08/18

- scripts kept outside the repo (scratchpad, `--root` only)
- snapshots are QUADRATIC: one per commit, each serializing
  the whole `G`, so total ~= 0.26 * N^2 KB
    - 25 posts: 228 KB, 14% of `.git`
    - 50 posts: 756 KB, 24%
    - 100 posts: 2740 KB, 40%
    - 200 posts: 10416 KB, 60%
    - x3.3, x3.6, x3.8 per doubling -> converging on x4
    - newest snapshot 12 -> 98 KB (linear in N)
    - extrapolated: 1k actions ~260 MB, 10k ~26 GB
- payload ref advertisement is LINEAR, and small
    - exactly 2*(payloads)+2 refs per incremental recv
    - the payload refs are advertised TWICE (two fetches)
    - ~316 trace-bytes per post per recv (~100 wire)
    - recv wall time 186 -> 509 ms over 10 -> 160 posts:
      fixed costs dominate, no O(N) term visible yet
- the refspec cliff is REAL and exact
    - `exec` is `io.popen` -> `sh -c "<one argument>"`
    - so the cap is MAX_ARG_STRLEN, not ARG_MAX
    - measured: 131071 bytes max for that argument
    - 58 bytes per negative refspec -> breaks at 2259
      revoked actions (E2BIG, a hard failure)

# E stage 2: prune `.git/states/` (do first)

- `sweep` (stage 1 = `git gc --prune=now`) gains stage 2:
  delete snapshots outside the settled window
- settled = below the hardfork window (fork.time/fork.actions)
- keep: window snapshots + the tips sync reads (HEAD, oct
  candidates); a missing interior snapshot must be
  recomputable or unreachable
- payoff: O(N^2) -> O(W*N), since each kept snapshot is still
  O(N); a ~100x cut, not constant space

## BLOCKER: `STATE.read` asserts on a miss

- `state.lua:31` -> `"bug found : no snapshot"`, no recompute
- tolerant readers (pruning is already safe for them):
    - `sync.lua:227` replay seeding just replays instead
    - `consensus.lua:232` writes what is missing
- fatal readers:
    - `init.lua:24` loads HEAD's snapshot for EVERY
      non-sync command
    - `abandon.lua` resets HEAD onto an arbitrary old
      commit ("lands on a tip whose snapshot already
      exists") -> every later command dies

## E0: snapshots become a true cache (before any delete)

- `STATE.read` falls back to replaying forward from the
  nearest ancestor snapshot
- self-contained, testable alone
- makes the stage 2 deletion trivially safe

# S6.0: chunk the negative refspecs (split out)

- the only item with a failure behind it today
- chunk `sync.lua:249-258` at ~1500 refspecs per `git fetch`
- do NOT drop the negatives instead: they are what stops
  revoked bytes from ever landing; the end-of-sync scan
  deletes the anchor only AFTER the bytes arrive

# S6.1 (postponed): explicit payload fetch list

- today recv ends with a whole-world reconcile: fetch
  `refs/payloads/*` minus the revoked, then scan all actions
- build `want[aid] = blob` DURING the replay
    - `commit()` already holds `act.blob` per applied action
    - fetch that EXPLICIT list, not `refs/payloads/*`
    - wildcard = server advertises one ref per action ever
      posted (O(chain) every sync)
    - chunk the list: `git fetch` takes no refspecs on stdin
- KEEP the end-of-sync scan as the authority for deletes
    - miss a fetch -> just missing bytes, next sync heals
    - miss a delete -> kept revoked bytes: the one promise
    - idempotent, self-healing, costs no network
- WHY POSTPONED
    - linear, and invisible in recv latency below ~200
    - the retained scan keeps per-sync work O(chain) anyway,
      so the win is partial
    - revisit after a measurement at 5k+ actions

# S6.2 (later): `apply()` emits anchor events

- `like.lua` already names them: REMOVAL (entered revoked)
  and LIFT (left revoked), same `cat-file -e` probe
- `like` consumes one, `sync` batches them: one path
- settle first: local LIFT can `ERROR("expected --file")`
  when bytes are gone; sync restore silently skips ->
  a sync can leave a standing post unanchored
