# 260818-payloads

- source: 260817-storage.md (split 26/08/18), section "S6"
- theme: `refs/payloads/`, what recv fetches and what it drops
- the postponed half, except S6.0

# Measured 26/08/18

- scripts kept outside the repo (scratchpad, `--root` only)
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

# S6.0: chunk the negative refspecs (do first)

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
