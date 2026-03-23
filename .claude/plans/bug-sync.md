# Bug: Sync Divergent Test Failure

## Symptom

`cli-sync.lua` Step 3 ("recv divergent") fails at line 124:
`A's should be in posts.lua`

After A recvs from B (divergent merge), `posts.lua` does not
contain A's post hash.
The `.txt` files are present (git merge worked), but the
replayed state is wrong.

## Test Flow (Step 3)

1. A posts "fourth from A" → hash A
2. B posts "second from B" → hash B
3. A recvs from B → divergent merge
4. Assert: `posts[A]` and `posts[B]` in `posts.lua` → FAILS

## Suspects

### 1. replay silently drops posts on apply failure (most likely)

`sync.lua:40-69` — `replay()` calls `apply(G, entry)` but
**ignores the return value**.
If `apply` returns `false` (validation failure), `G.posts[hash]`
is never set, and replay silently continues.

This can happen if time_effects during replay changes reps
through discount/consolidation, causing a previously-valid post
to fail the `reps <= 0` check.

**Location**: `src/freechains/chain/sync.lua:57-63`

### 2. now.lua never written by sync (secondary bug)

`sync.lua:166-167` writes `authors.lua` and `posts.lua` but
NOT `now.lua`.
`init.lua:29` writes `now.lua`, but only in the non-sync branch.
So after sync, `now.lua` on disk is stale.

This doesn't explain the current failure (replay uses in-memory
`G.now`), but will cause incorrect time_effects on subsequent
operations.

**Location**: `src/freechains/chain/sync.lua:166-167`

### 3. stash drop commented out (minor)

`sync.lua:153` — `stash drop` is commented out.
The stash accumulates across syncs.
Not the cause of this failure but should be cleaned up.

**Location**: `src/freechains/chain/sync.lua:153`

## Debug Plan

Add debug write in `replay()` after each `apply` call to
confirm suspect #1:

```lua
-- in replay(), after apply call:
local ok, err = apply(G, { ... })
local f = io.open("/tmp/dbg.txt", "a")
f:write("replay: " .. hash .. " ok=" .. tostring(ok)
    .. " err=" .. tostring(err) .. "\n")
f:close()
```

If any `ok=false` appears, the root cause is confirmed:
replay needs to either handle the failure (discard branch)
or the validation threshold needs adjustment for replay
context.

## Status

- [ ] Add debug lines to replay
- [ ] Run test, inspect `/tmp/dbg.txt`
- [ ] Identify which validation check fails and why
- [ ] Fix replay / apply interaction
- [ ] Fix now.lua write in sync
- [ ] Clean up stash drop
