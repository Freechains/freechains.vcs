# Payload fetch: check what the remote sends (26/10/29)

# Context

- main `sync.lua` recv, payload pass (~ln 257-315)
- fetch `refs/payloads/*`, minus one negative refspec per
  revoked post
- replaces branch 261015-fetch-argmax (main form)

# Problem

- the remote may advertise any `refs/payloads/<name>`
- nothing checks what arrives:
    - unknown name (not in `G.actions`): kept forever
    - known cid, wrong blob: kept, `has[cid]` skips the check
        - `get` reads `t.blob`: never served, but missing
        - the real blob is never fetched
        - the bad ref spreads to our own peers
- the negative refspecs only save bandwidth:
    - the revoked loop deletes them after the fetch anyway
    - ~2260 revoked pass the 128 KB `sh -c` cap
      (261015-fetch-argmax)

# Fix

- fetch the glob only: drop the negative refspecs
- after the fetch, check every `refs/payloads/<x>`:
    - keep: `x` is a non-revoked action, ref == `t.blob`
    - else: delete the ref
- keep the restore branch (missing ref, blob in odb)
- `exec`: raise "bug found" on a nil `popen`
  (from 261015-fetch-argmax)
- orphan blobs (revoked, bogus): left to `gc`

# Open

- revoked bytes still land on disk until `gc`
    - ok unless a takedown requires never storing them
- one `for-each-ref` + reads per recv: cost at 50k posts
- ia-optim: blobs fetched by id, already checked

# Status

- [ ] fix in `sync.lua`
- [ ] nil `popen` check in `common.lua`
- [ ] drop `tst/bug-fetch-argmax.lua` (main form)?
