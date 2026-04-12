# Bug: Sync Divergent Test Failure

## Status: RESOLVED

All three suspects were fixed in the current codebase.
All sync tests pass (Steps 1-6b).

## Resolution

1. `replay()` now checks `apply()` return values and
   returns early on failure (sync.lua lines 105-116)
2. `now.lua` handling removed (no longer relevant)
3. `stash drop` cleaned up (no longer present)

## Original Symptom

`cli-sync.lua` Step 3 ("recv divergent") failed at line 124:
`A's should be in posts.lua`

After A recvs from B (divergent merge), `posts.lua` did not
contain A's post hash.
The `.txt` files were present (git merge worked), but the
replayed state was wrong.

## Checklist

- [x] Add debug lines to replay
- [x] Run test, inspect `/tmp/dbg.txt`
- [x] Identify which validation check fails and why
- [x] Fix replay / apply interaction
- [x] Fix now.lua write in sync
- [x] Clean up stash drop
