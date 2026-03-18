# Bug: posts.lua keyed by blob hash, likes use commit hash

## Problem

Post creation keys `posts.lua` by **blob hash**
(content hash), but likes target posts by **commit
hash**.
This creates two separate entries for the same post:

- `posts[blob]` — has state (blocked, 00-12, etc.),
  author, time
- `posts[commit]` — created by like via `or` fallback,
  has only reps

Consequences:
- Like reps go to the wrong entry
- Discount/consolidation scans miss liked posts
- Blob hash is semantically wrong: a blob has no
  author, two identical posts produce the same key

## Fix

Switch `posts.lua` key from blob hash to commit hash.

### Current flow (chain.lua)

```
1. compute blob hash (line 171/186)
2. write G.posts[blob] = { ... }  (line 252)
3. write local/posts.lua           (line 283)
4. git add + git commit            (line 286-300)
5. hash = git rev-parse HEAD       (line 303)
6. if beg: update-ref + reset      (line 308-313)
7. print(hash)                     (line 315)
```

### New flow

```
1. compute blob hash (for filename only)
2. git add + git commit
3. hash = git rev-parse HEAD
4. write G.posts[hash] = { ... }
5. write local/posts.lua
6. if beg: update-ref + reset
7. print(hash)
```

Key change: posts.lua write moves AFTER the commit,
using the commit hash as key instead of blob hash.

## Files to Modify

| File                       | Place     | Change                          |
|----------------------------|-----------|---------------------------------|
| `src/freechains/chain.lua` | line 252  | `G.posts[blob]` -> after commit |
| `src/freechains/chain.lua` | line 283  | move write after commit         |
| `src/freechains/chain.lua` | line 267  | no change (already uses commit) |
| `src/freechains/chain.lua` | line 107  | no change (ARGS.key from CLI)   |
| `tst/cli-begs.lua`         | lines 42-61  | simplify: `posts[BEG]`      |
| `tst/cli-begs.lua`         | lines 173-185| simplify: `posts[BEG]`      |
| `tst/cli-reps.lua`         | check        | may use blob hash in queries |
| `tst/cli-like.lua`         | check        | may use blob hash in queries |

## Implementation Steps

### Step 1: Restructure chain.lua post flow

Move the `G.posts[key] = { ... }` write and the
`write(G.posts, ...)` call to after the commit.
Use `hash` (commit hash from `rev-parse HEAD`)
instead of `blob`.

Before (current order):
```
metadata write -> git add -> commit -> rev-parse
```

After:
```
git add -> commit -> rev-parse -> metadata write
```

Note: `G.authors` updates (cost deduction, time init)
can stay before the commit — they don't depend on the
commit hash.
Only `G.posts[key]` needs the commit hash.

### Step 2: Review chain.lua like flow

No structural change needed.
`G.posts[ARGS.id]` already uses commit hash.
The `or { reps=0, author=a }` fallback now correctly
creates an entry for posts that were created before
this code change (backwards compat).

### Step 3: Update cli-begs.lua tests

Replace blob hash extraction with direct commit hash:

Before:
```lua
local file = exec(true, "git diff-tree ..." .. BEG)
local txt = exec(true, "git show " .. BEG .. ":" .. file)
local hash = exec(true,
    "echo " .. txt .. " | git hash-object --stdin")
assert(posts[hash], ...)
```

After:
```lua
assert(posts[BEG], "post entry not found: " .. BEG)
```

### Step 4: Check other tests

Review `cli-reps.lua` and `cli-like.lua` for any
blob-hash assumptions in post lookups.

### Step 5: Run all tests

## Dependencies

- Simplifies begs.md fetch registration
  (commit hash = ref target, no blob extraction)

## Done

## TODO

- [x] Step 1: Restructure chain.lua post flow
- [x] Step 2: Review chain.lua like flow (no change needed)
- [x] Step 3: Update cli-begs.lua tests (posts[BEG])
- [x] Step 4: Check other tests (no blob hash assumptions)
- [x] Step 5: Run all tests
- [x] Refactor: remove blob from filenames (time+rand only)
- [x] Refactor: beg ref uses commit hash (beg-time-hash)
- [x] Refactor: xas/xps dirty flags for writes
