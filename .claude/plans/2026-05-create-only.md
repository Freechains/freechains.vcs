# Create-Only Milestone

## Status: Proposal

Date: 2026-05-02

Implement **only** the `create` mode from
[operations.md](operations.md) as the first milestone.
The full 4-way design (`create` < `append` < `remove` < `edit`)
is deferred — see operations.md for the target spec.

## Scope

- Only `create` mode exists for now.
- **No** `mode` field in `.freechains/config.lua` yet.
  (Defer the schema change until at least 2 modes exist.)
- Behavior is **hardcoded** to `create` everywhere.
- All existing chains are implicitly `create`-mode.

## Goal

Guarantee that every commit on every chain is a pure
**create** — only new files, no overwrites, no extends, no
deletions, no rewrites.

This must hold even when the user bypasses `freechains chain
post` and uses `git commit` directly, because the local working
tree is a real git repository.

## Enforcement points

| Layer       | File                              | Where                           |
|-------------|-----------------------------------|---------------------------------|
| client tip  | `src/freechains/chain/post.lua`   | before `git add` / `git commit` |
| sync recv   | `src/freechains/chain/sync.lua`   | inside `commit()` (~L109)       |

**Why both:**

- `post.lua` — fail fast in the happy path with a clean error.
- `sync.lua:commit` — already iterates loser-branch and
  remote-replay commits via `climb()`. Catches raw-git commits
  pushed by peers (the network invariant).

The FF path does **not** need a separate check: `climb()` runs
before the FF block (~L263) and validates every commit in
`oct..rem` via `commit()`. If `loc` is ancestor of `rem`, then
`oct == loc`, so every new commit was validated.

The pre-receive hook (`src/freechains/hooks/pre-receive`)
already routes every push through `chain sync recv`, so the
single `commit()` call site covers both push and recv directions.

### Check block

Inlined inside `sync.lua:commit()` for `kind=='post'` and
`kind=='like'` (state commits are exempt, see below).
Single call site — no helper function needed.

Stricter rule: **exactly one file, status `A`**.
Merge commits skipped (constituent commits already validated).

```lua
-- in sync.lua:commit(), guarded by kind ~= 'state'
do
    -- skip merge commits: parents already validated
    local ps = exec (
        "git -C " .. REPO .. " rev-list --parents -1 " .. hash
    )
    local n = 0
    for _ in ps:gmatch("%x+") do
        n = n + 1
    end
    if n <= 2 then
        local out = exec (
            "git -C " .. REPO ..
            " diff-tree -r --name-status --root " ..
            hash .. "^ " .. hash
        )
        local count = 0
        for status, path in out:gmatch("(%a)%s+(%S+)") do
            if status ~= "A" then
                error (
                    "invalid " .. kind ..
                        " : create-mode violation : " ..
                        status .. " " .. path
                    , 0
                )
            else
                count = count + 1
            end
        end
        if count ~= 1 then
            error (
                "invalid " .. kind ..
                    " : expected 1 file, got " .. count
                , 0
            )
        end
    end
end
```

### State commits

State commits (trailer `Freechains: state`) write
`.freechains/state/{authors,posts,order}.lua`.
Those paths are mutated by design — they are an internal index,
not user content.

Two options:

1. **Skip mode check for `kind == 'state'`.** Same path the
   existing validator already takes (sync.lua:169).
2. **Restrict the check to non-state paths** (filter out
   `.freechains/state/*` in the diff).

Recommendation: option 1. State commits are a closed set
produced only by freechains itself; trusting their kind trailer
matches existing design.

## `post` cleanup

The current `post` implementation has three behaviors that
violate `create` mode silently
(`src/freechains/chain/post.lua`):

| Loc                                          | Current                                                      | Change                                  |
|----------------------------------------------|--------------------------------------------------------------|-----------------------------------------|
| post.lua:12                                  | `text = ARGS.text .. (..."\n" if missing)`                   | drop the implicit `\n` — write verbatim |
| post.lua:15                                  | `io.open(..., (ARGS.file and "a") or "w")`                   | use `"w"` always; reject if file exists |
| post.lua:22-24                               | `cp ARGS.path REPO/`                                         | reject if destination exists in tree    |

After this, `post` always produces a single new file.
No append, no overwrite, no `\n` mutation.

### Why drop implicit `\n`

`create` mode is byte-faithful: the blob in git must equal the
bytes the user posted.
post.lua:12 silently appends `\n` when missing, so the blob
diverges from user input.
Drop it; if a user wants a trailing newline, they include one.

This change also fixes the misleading test at
`tst/cli-post.lua:102`:
```lua
assert(content == "Line 1", "content: " .. content)
```
which only matches because `exec("cat ...")` strips the
trailing `\n` from its return value — disk content is actually
`"Line 1\n"`.
After the cleanup, both the disk content and the read result
will be `"Line 1"`.

## Test plan

### Positive

| #  | Test                                                          |
|----|---------------------------------------------------------------|
| 1  | `post inline 'X'` (auto-named) → ok, blob is exactly `"X"`    |
| 2  | `post file new.txt` (new path) → ok, blob is byte-faithful    |
| 3  | Two distinct posts to two distinct files → both succeed       |

### Negative — `post`-level

| #  | Test                                                          |
|----|---------------------------------------------------------------|
| 4  | `post inline 'X' --file existing.txt` → reject                |
| 5  | `post file existing-path` → reject                            |
| 6  | `post inline 'X'` does not append `\n`                        |

### Negative — raw-git bypass

| #  | Test                                                          |
|----|---------------------------------------------------------------|
| 7  | Raw `git commit` overwriting a tracked file, then `sync send` → peer rejects (`commit()` validation) |
| 8  | Raw `git rm` of a tracked file, then `sync send` → peer rejects |
| 9  | Raw `git commit` rewriting tracked file, then peer FF-pulls → peer rejects in FF path |
| 10 | Raw `git commit` adding a new file (only) → accepted          |

## Migration to full 4-way

When [operations.md](operations.md) is implemented:

1. Add `mode` field to `config.lua` schema.
2. Replace the inlined create check in `sync.lua:commit()` with
   a `check_mode(hash, mode)` dispatching on the chain's mode.
3. Update existing chains: treat absence of `mode` as `create`
   (matches today's invariant).
4. Drop the hardcoded create-only assumption in `post.lua`;
   route file-write semantics by mode.

No reflows of git history are required — the byte-faithful
`create` blobs are valid `create` blobs in the future scheme too.

## Implementation checklist

- [ ] Inline create check in `sync.lua:commit()` for `kind=='post'` and `kind=='like'`
- [ ] Drop `\n` rewrite in `post.lua:12`
- [ ] Replace `"a"`/`"w"` selector with `"w"` + pre-existence check
- [ ] Reject existing destination in `post file` (post.lua:22-24)

## Open questions

1. Should `post` have an explicit `--overwrite` flag for the
   future `edit` mode, or is mode policy alone enough?
   (Defer until 4-way lands.)
2. Should the genesis state commit be exempted as a special
   case, or detected via its trailer like other state commits?
   (Likely already covered by trailer check; verify.)
