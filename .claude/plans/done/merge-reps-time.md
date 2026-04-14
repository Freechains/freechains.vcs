# Merge reps/ and time/ into unified authors.lua + posts.lua

## Context

Currently each entity's state is split across 4 files:
- `reps/authors.lua` — pubkey → internal rep
- `reps/posts.lua` — hash → internal rep
- `time/authors.lua` — pubkey → last grant timestamp
- `time/posts.lua` — array of posts in discount/consolidation

Problems:
- Authors only appear in `reps/authors.lua` if they have
  non-zero rep changes (pioneers or liked). Non-pioneer
  signers are invisible.
- Posts only appear in `reps/posts.lua` if they received
  likes. Regular posts are invisible.
- `reps authors` / `reps posts` list commands were
  commented out because they couldn't list all entities.

## Goal

Merge into 2 files under `.freechains/`:
- **`authors.lua`** — ALL signing authors
- **`posts.lua`** — ALL created posts

Keep `likes/` as-is (git commit content for like ops).

## New File Formats

### authors.lua

```lua
return {
    ["CA6391CE..."] = { reps=29000, time=1710374400 },
    ["78397501..."] = { reps=0 },
}
```

- `reps`: internal reputation (1000x)
- `time`: last grant-slot timestamp (nil/absent if never
  posted, present from first signed post)
- Pioneers start with `{ reps=30000 }` (no time yet)
- Non-pioneers added on first signed post: `{ reps=0 }`

### posts.lua

```lua
return {
    ["a1b2c3d4..."] = { reps=0, author="CA6391CE...", time=1710288000, state="00-12" },
    ["e5f6g7h8..."] = { reps=1350 },
}
```

- `reps`: accumulated like/dislike score
- `author`, `time`, `state`: present while in
  discount/consolidation (replaces time/posts.lua)
- After consolidation completes: only `reps` remains
  (author/time/state removed)
- Entry created on post commit with
  `{ reps=0, author=..., time=NOW, state="00-12" }`

## Files to Modify

| File                                          | Changes                                        |
|-----------------------------------------------|------------------------------------------------|
| `src/freechains/chain.lua`                    | Main refactor: unified load/write, scans       |
| `lua/freechains/skel/.freechains/authors.lua` | New skel (replaces reps/authors + time/authors)|
| `lua/freechains/skel/.freechains/posts.lua`   | New skel (replaces reps/posts + time/posts)    |
| `src/freechains/chains.lua`                   | Update skel copy if paths change               |
| `tst/genesis-1p/authors.lua`                  | New format: `{ reps=30000 }`                   |
| `tst/genesis-2p/authors.lua`                  | New format                                     |
| `tst/genesis-3p/authors.lua`                  | New format                                     |
| `tst/cli-reps.lua`                            | Adapt tests to new behavior                    |

### Files to Remove

- `lua/freechains/skel/.freechains/reps/` (entire dir)
- `lua/freechains/skel/.freechains/time/` (entire dir)
- `tst/genesis-*/reps/` (move to genesis-*/authors.lua)

## Implementation Steps

### 1. Update skel and genesis templates

New skel files at `.freechains/`:
- `authors.lua` → `return {}`
- `posts.lua` → `return {}`

Remove skel dirs: `reps/`, `time/`.

Update genesis dirs, e.g. `tst/genesis-1p/authors.lua`:
```lua
return {
    ["CA6391CE..."] = { reps=30000 },
}
```

### 2. Update chains.lua (init)

Adjust `skel()` / chain creation to use new paths.
Genesis overlay copies `authors.lua` (not
`reps/authors.lua`).

### 3. Refactor chain.lua — loading

Replace:
```lua
fc_reps_authors = dofile(... "reps/authors.lua")
fc_time_posts   = dofile(... "time/posts.lua")
fc_time_authors = dofile(... "time/authors.lua")
```

With:
```lua
fc_authors = dofile(... "authors.lua")
fc_posts   = dofile(... "posts.lua")
```

### 4. Refactor chain.lua — discount scan

Iterate `fc_posts` (checking `entry.state == "00-12"`)
instead of `fc_time_posts` array.

Access author reps via `fc_authors[key].reps`.
Access author time via `fc_authors[key].time`.

### 5. Refactor chain.lua — consolidation scan

Iterate `fc_posts` for `state == "12-24"`.
On consolidation: clear `time` and `state` from post
entry, keep `reps` and `author`.

### 6. Refactor chain.lua — post handler

On signed post, use the blob object hash (already
computed for the filename via `git hash-object`) as
the post key:
```lua
fc_authors[ARGS.sign] = fc_authors[ARGS.sign] or { reps=0 }
fc_authors[ARGS.sign].reps = fc_authors[ARGS.sign].reps - C.reps.cost
if fc_authors[ARGS.sign].time == nil then
    fc_authors[ARGS.sign].time = NOW.s
end
fc_posts[blob] = { reps=0, author=ARGS.sign, time=NOW.s, state="00-12" }
```

`blob` is the full object hash from `git hash-object`.
Known before commit — no circularity.

### 7. Refactor chain.lua — like handler

Access `fc_posts[ARGS.id].reps` directly (no dofile).

For post-targeted likes, get author from
`fc_posts[ARGS.id].author` (always present — kept
after consolidation).

### 8. Refactor chain.lua — queries

- `reps author <key>`: `fc_authors[key].reps`
- `reps post <hash>`: `fc_posts[hash].reps`
- Uncomment `reps authors` / `reps posts` list
  commands — now listing ALL entries.

### 9. Refactor chain.lua — writing

Replace 3 writes with 2:
```lua
write(fc_authors, ... "authors.lua")
write(fc_posts,   ... "posts.lua")
```

Update `files` string for git add accordingly.

## Resolved Questions

1. **Post key**: use the blob object hash (already
   computed for the filename via `git hash-object`),
   not the commit hash. No circularity —
   `posts.lua` stays git-tracked.

2. **Consolidation cleanup**: strip `time` and `state`,
   keep `reps` and `author`:
   `{ reps=1350, author="CA6391CE..." }`
   Author preserved so like handler never needs git
   log fallback.

## Done

- [x] Step 1: Update skel and genesis templates
- [x] Step 2: Update chains.lua (no change needed)
- [x] Step 3: Refactor chain.lua — loading (G.authors/G.posts)
- [x] Step 4: Refactor chain.lua — discount scan
- [x] Step 5: Refactor chain.lua — consolidation scan
- [x] Step 6: Refactor chain.lua — post handler (blob key)
- [x] Step 7: Refactor chain.lua — like handler
- [x] Step 8: Refactor chain.lua — queries (authors/posts uncommented)
- [x] Step 9: Refactor chain.lua — writing (2 files)
- [x] Tests: cli-post, cli-sign, cli-like, cli-reps all pass
- [x] Fix: cli-like diff-tree filter for likes/ dir
- [x] Fix: blob hash fallback for post file path

## TODO
