# Author Hash: Add Author Key to Post Filenames

## Goal

Include author key in filename hashing to make filenames
unique per author.
Remove `--allow-empty` from git commit.

## Current State

`chain.lua` uses blob hash only for naming:

| Place   | Line | Pattern                                    |
|---------|------|--------------------------------------------|
| post    | 174  | `post-<NOW.s>-<blob:sub(1,8)>.txt`        |
| like    | 219  | `like-<NOW.s>-<blob:sub(1,8)>.lua`        |
| beg ref | 308  | `refs/begs/<NOW.s>-<blob:sub(1,8)>`       |

Problem: two authors posting identical content at same
timestamp produce the same filename.
The commit has no diff, so `--allow-empty` (line 299) is
needed as a safety net.

## Proposed Change

Hash `blob .. ARGS.sign` instead of just `blob`:

```lua
local id = exec(
    "printf '%s' '" .. blob .. ARGS.sign
    .. "' | git hash-object --stdin"
)
```

New naming:

| Place   | Pattern                                      |
|---------|----------------------------------------------|
| post    | `post-<NOW.s>-<id:sub(1,8)>.txt`            |
| like    | `like-<NOW.s>-<id:sub(1,8)>.lua`            |
| beg ref | `refs/begs/<NOW.s>-<id:sub(1,8)>`           |

Then remove `--allow-empty` from line 299.

## Require --sign for begs

Currently `--beg` without `--sign` is allowed
(chain.lua lines 159-163).
Change to require both:

- Author identity needed for filename hash
- Author identity needed for reputation tracking
  (likes target an author)
- `cli-begs.lua` already uses `--beg --sign KEY2`

Remove the `else` branch that allows bare `--beg`.

## Files to Modify

| File                      | Place          | Change                        |
|---------------------------|----------------|-------------------------------|
| `src/freechains/chain.lua`| line 174       | post filename: hash blob+sign |
| `src/freechains/chain.lua`| line 219       | like filename: hash blob+sign |
| `src/freechains/chain.lua`| line 299       | remove `--allow-empty`        |
| `src/freechains/chain.lua`| line 308       | beg ref: hash blob+sign       |
| `src/freechains/chain.lua`| lines 159-163  | remove --beg without --sign   |
| `tst/cli-begs.lua`        | lines 43, 174  | fix path: local/posts.lua     |
| `tst/cli-sign.lua`        | line 48        | `--beg` needs `--sign` now    |
| `tst/repl-local-begs.lua` | all --beg      | `--beg` -> `--beg --sign KEY` |
| `tst/repl-remote-begs.lua`| all --beg      | `--beg` -> `--beg --sign KEY` |

## Implementation Steps

### Step 1: chain.lua -- compute combined hash

After blob is computed (both post and like paths),
compute combined id:

```lua
local id = exec(
    "printf '%s' '" .. blob .. ARGS.sign
    .. "' | git hash-object --stdin"
)
```

Use `id` instead of `blob` in all three naming sites.

### Step 2: chain.lua -- update naming

Replace `blob:sub(1,8)` with `id:sub(1,8)` at:
- line 174 (post filename)
- line 219 (like filename)
- line 308 (beg ref name)

### Step 3: chain.lua -- remove --allow-empty

Line 299: remove `--allow-empty` from commit command.
Keep `--allow-empty-message` (empty messages are valid).

### Step 4: chain.lua -- require --sign for begs

Lines 159-163: remove the `else` branch that allows
`--beg` without `--sign`.
Error message: `chain post : --beg requires --sign`

### Step 5: Update tests

- `cli-begs.lua` lines 43, 174:
  `.freechains/posts.lua` -> `.freechains/local/posts.lua`
- `cli-sign.lua` line 48:
  `--beg` -> `--beg --sign KEY2` (needs a non-pioneer key)
- `repl-local-begs.lua`:
  all `--beg` -> `--beg --sign KEY`
- `repl-remote-begs.lua`:
  all `--beg` -> `--beg --sign KEY`

### Step 6: Run all tests

- `cli-post`, `cli-sign`, `cli-begs`
- `cli-like`, `cli-reps`, `cli-time`
- `repl-local-head`, `repl-remote-head`
- `repl-local-begs`, `repl-remote-begs`

## Dependencies

- `begs.md` depends on this (begs require --sign)

## Done

## TODO

- [ ] Step 1: Compute combined hash
- [ ] Step 2: Update naming (3 sites)
- [ ] Step 3: Remove --allow-empty
- [ ] Step 4: Require --sign for begs
- [ ] Step 5: Update tests
- [ ] Step 6: Run all tests
