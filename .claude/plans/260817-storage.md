# 260817-storage

- source: done/280808-redesign.md, sections "S6" and E stage 2
- theme: what bytes live where, and when they die

# E stage 2: prune `.git/states/`

- `sweep` (stage 1 = `git gc --prune=now`) gains stage 2:
  delete snapshots outside the settled window
- settled = below the hardfork window (fork.time/fork.posts)
- keep: window snapshots + the tips sync reads (HEAD, oct
  candidates); a missing interior snapshot must be
  recomputable or unreachable
- one snapshot per commit forever otherwise

# S6.1: explicit payload fetch list

- today recv ends with a whole-world reconcile: fetch
  `refs/payloads/*` minus the revoked, then scan all actions
- build `want[aid] = blob` DURING the replay
    - `commit()` already holds `act.blob` per applied action
    - fetch that EXPLICIT list, not `refs/payloads/*`
    - wildcard = server advertises one ref per action ever
      posted (O(chain) every sync)
    - kills the negative refspecs, which are argv: many
      revocations can hit `ARG_MAX`
    - chunk the list: `git fetch` takes no refspecs on stdin
- KEEP the end-of-sync scan as the authority for deletes
    - miss a fetch -> just missing bytes, next sync heals
    - miss a delete -> kept revoked bytes: the one promise
    - idempotent, self-healing, costs no network

# S6.2 (later): `apply()` emits anchor events

- `like.lua` already names them: REMOVAL (entered revoked)
  and LIFT (left revoked), same `cat-file -e` probe
- `like` consumes one, `sync` batches them: one path
- settle first: local LIFT can `ERROR("expected --file")`
  when bytes are gone; sync restore silently skips ->
  a sync can leave a standing post unanchored
