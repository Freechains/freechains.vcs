# Unique Filenames: Random Suffix

## Goal

Add a random number to post/like/beg filenames to
guarantee uniqueness.
Remove `--allow-empty` from git commit.

## Current State

`chain.lua` uses blob hash only for naming:

| Place   | Line | Pattern                                    |
|---------|------|--------------------------------------------|
| post    | 174  | `post-<NOW.s>-<blob:sub(1,8)>.txt`        |
| like    | 219  | `like-<NOW.s>-<blob:sub(1,8)>.lua`        |
| beg ref | 308  | `refs/begs/<NOW.s>-<blob:sub(1,8)>`       |

Problem: two posts with identical content at the same
timestamp produce the same filename.
The commit has no diff, so `--allow-empty` (line 299)
is needed as a safety net.

## Proposed Change

Append a random number to the filename:

```lua
local rand = math.random(0, 0xFFFFFFFF)
```

New naming:

| Place   | Pattern                                            |
|---------|----------------------------------------------------|
| post    | `post-<NOW.s>-<blob:sub(1,8)>-<rand>.txt`         |
| like    | `like-<NOW.s>-<blob:sub(1,8)>-<rand>.lua`         |
| beg ref | `refs/begs/<NOW.s>-<blob:sub(1,8)>-<rand>`        |

The blob hash stays (content-addressable for lookups).
The random suffix guarantees uniqueness.
Determinism in filenames serves no purpose -- the post
key in `posts.lua` is the full blob hash, already
deterministic.

Then remove `--allow-empty` from line 299.

## Security

No attack vector from random filenames:
- Post identity in `posts.lua` uses the **full blob
  hash**, not the filename.
- A crafted collision (same time + blob prefix + rand)
  would at worst cause: file exists -> `git add` shows
  no diff -> commit fails -> **error to user**.
- Removing `--allow-empty` is a bonus defense: turns
  a silent collision into a visible error.
- Random range (`0xFFFFFFFF` = 4 billion) makes
  accidental collisions near-impossible.

## Files to Modify

| File                       | Place         | Change                    |
|----------------------------|---------------|---------------------------|
| `src/freechains/chain.lua` | line 174      | append rand to post name  |
| `src/freechains/chain.lua` | line 219      | append rand to like name  |
| `src/freechains/chain.lua` | line 299      | remove `--allow-empty`    |
| `src/freechains/chain.lua` | line 308      | append rand to beg ref    |
| `tst/cli-begs.lua`         | lines 43, 174 | fix path: local/posts.lua |

## Implementation Steps

### Step 1: chain.lua -- generate random

Near the top of the post/like block, generate one
random number for the current operation:

```lua
local rand = math.random(0, 0xFFFFFFFF)
```

Note: `math.randomseed()` is called in `chains.lua`.
Verify it is also seeded before `chain.lua` runs
(or seed it here).

### Step 2: chain.lua -- update naming (3 sites)

Append `-<rand>` to the name at:

- line 174 (post filename):
  `"post-" .. NOW.s .. "-" .. blob:sub(1,8)
  .. "-" .. rand .. ".txt"`
- line 219 (like filename):
  `"like-" .. NOW.s .. "-" .. blob:sub(1,8)
  .. "-" .. rand .. ".lua"`
- line 308 (beg ref name):
  `"refs/begs/" .. NOW.s .. "-" .. blob:sub(1,8)
  .. "-" .. rand`

### Step 3: chain.lua -- remove --allow-empty

Line 299: remove `--allow-empty` from commit command.
Keep `--allow-empty-message` (empty messages are valid).

### Step 4: Fix cli-begs.lua paths

Lines 43, 174:
`.freechains/posts.lua` -> `.freechains/local/posts.lua`

### Step 5: Update tests for new filename pattern

Tests that match filenames may need pattern updates
to account for the extra `-<rand>` segment.

Check:
- `cli-post.lua` line 89: `post%-(%x+)%.txt` pattern
- `cli-begs.lua` lines 44-48: diff-tree file pattern

### Step 6: Run all tests

- `cli-post`, `cli-sign`, `cli-begs`
- `cli-like`, `cli-reps`, `cli-time`
- `repl-local-head`, `repl-remote-head`
- `repl-local-begs`, `repl-remote-begs`

## Dependencies

- None. Independent of begs.md.

## Done

## TODO

- [ ] Step 1: Generate random
- [ ] Step 2: Update naming (3 sites)
- [ ] Step 3: Remove --allow-empty
- [ ] Step 4: Fix cli-begs.lua paths
- [ ] Step 5: Update test patterns
- [ ] Step 6: Run all tests
