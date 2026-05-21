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

Inlined inside `sync.lua:commit()`. Single call site — no helper
function needed. Two branches: state and non-state.

Uses `diff-tree --cc` to unify merge and non-merge handling:

- non-merge: `--cc` falls back to regular diff vs parent;
  status is single-char (`A`, `M`, `D`, ...).
- merge: `--cc` shows only **novel** content (files where the
  result differs from every parent); status is multi-char
  (`AA`, `AM`, `MM`, ...). `AA` = added vs both parents = OK.

Rules per kind:

| kind         | path restriction                                      | status restriction |
|--------------|-------------------------------------------------------|--------------------|
| `post`/`like`| any                                                   | `A` only           |
| `state`      | exactly `.freechains/state/{authors,posts,order}.lua` | `A` or `M` only    |

```lua
local diff = exec (
    "git -C " .. REPO ..
        " diff-tree --cc --no-commit-id -r --name-status " .. hash
)
if kind == 'state' then
    for status, path in diff:gmatch("(%a+)%s+(%S+)") do
        if path ~= ".freechains/state/authors.lua"
            and path ~= ".freechains/state/posts.lua"
            and path ~= ".freechains/state/order.lua"
        then
            error("invalid state : forbidden path : " .. path, 0)
        end
        if status:match("[^AM]") then
            error (
                "invalid state : forbidden status : " ..
                    status .. " " .. path
                , 0
            )
        end
    end
else
    for status, path in diff:gmatch("(%a+)%s+(%S+)") do
        if status:match("[^A]") then
            error (
                "invalid " .. kind ..
                    " : mode violation : " ..
                    status .. " " .. path
                , 0
            )
        end
    end
end
```

**Note:** `--no-commit-id` is required — without it, `diff-tree`
prints the commit hash as the first line, and the regex
`(%a+)%s+(%S+)` can mis-parse the trailing letters of the hash
as a "status" (flaky based on hash content).

Like-merges (`like.lua:37+71`) pass: the merge introduces one
new metadata file, status `AA`, no other novel content.

### State commits

State commits (trailer `Freechains: state`) write
`.freechains/state/{authors,posts,order}.lua`.
Those paths are mutated by design — they are an internal index,
not user content.

State is **not exempt** — it has its own restrictions:

- **Closed path set:** only the three files above. Anything else
  (including other `*.lua` files under `state/`) is rejected.
- **Allowed statuses:** `A` (initial / genesis) or `M` (mutate).
  `D` is rejected — state files are never deleted.

Without these restrictions, a state-trailer commit would be an
unrestricted attacker channel.

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

- [x] Inline create check in `sync.lua:commit()` for `kind=='post'` and `kind=='like'`
- [x] Add state branch: closed path set + `A`/`M` status only
- [x] Drop `\n` rewrite in `post.lua:12`
- [x] Replace `"a"`/`"w"` selector with `"w"` + pre-existence check
- [x] Reject existing destination in `post file` (post.lua:22-24)

## Deferred

- **Per-blob size cap.** Apply to all kinds (post, like, state).
  Implementation sketch: after the path/status loop, call
  `git cat-file -s <hash>:<path>` for each affected path and
  reject if size > `C.size.max`. State files grow with chain
  size — may need a higher state cap or be unbounded.
  Open: single global cap vs. per-kind caps; reasonable value.

## Open questions

1. Should `post` have an explicit `--overwrite` flag for the
   future `edit` mode, or is mode policy alone enough?
   (Defer until 4-way lands.)
2. Should the genesis state commit be exempted as a special
   case, or detected via its trailer like other state commits?
   (Likely already covered by trailer check; verify.)
