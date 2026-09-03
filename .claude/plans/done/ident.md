# Replace "beg" with "ident" commits

## SUPERSEDED

This plan was written before the GPG → SSH migration.
Key assumptions (GPG keyring, `.asc` files, `%GK`,
`GNUPGHOME`) no longer apply.
See `gpg-to-ssh.md` and `signing.md` for the current
SSH-based identity model.
The ident concept itself is out of scope for the SSH
migration and has not been implemented.

## Status

**Done (preparation):**
- Pioneer format migrated to
  `{ name, type, key, base64 }`
- `tst/genesis-1.lua`, `genesis-2.lua`, `genesis-3.lua`
  updated with new format
- `chains.lua` `pioneers()` writes keyring files into
  `.freechains/keys/` (`.asc` for GPG,
  `allowed_signers` for SSH)
- `skel/.freechains/keys/.gitkeep` added
- All existing tests pass

**Pending:** Steps 1–9 below.

## Keyring location

The keyring lives at `.freechains/keys/`, **outside** of
`state/`.

Reasons:
- `state/**` has `merge=ours` which would discard remote
  keyring additions during sync — keys could not propagate
  between peers.
- One file per key — every peer ends up with identical
  blob hashes, so commit history converges.

Layout:
- `.freechains/keys/<KEY>.asc` (GPG) — one file per key
- `.freechains/keys/<KEY>.pub` (SSH) — one file per key

### SSH verification: assembled `allowed_signers`

`git verify-commit` for SSH requires
`gpg.ssh.allowedSignersFile=<single-file>`. We don't commit
this file. Instead, before verification, we assemble it
from the per-key files into an **untracked** location:

```
.git/info/allowed_signers
```

Built deterministically (sorted by filename) from
`.freechains/keys/*.pub` whenever needed. Same pattern as
the GPG verification flow already described in
[signing.md](signing.md), where an ephemeral `GNUPGHOME`
is built from `.freechains/keys/*.asc`.

Pros:
- Per-key files merge cleanly across peers (identical blob
  hashes, no conflicts)
- No `merge=union` needed
- Commit history converges across peers
- Verification material is rebuilt locally, never
  replicated

## Context

The "beg" mechanism lets unknown users request entry into a
chain by posting unsigned content on an off-main branch
(`refs/begs/`), approved via a like.
This is being replaced by "ident" commits — a dedicated
commit type that registers a key in the chain's keyring.
Ident IS the new beg: "I want to join this chain."

The `--beg` flag on `post` is removed entirely.
Users without reputation use `ident` first, then `post`
(which appends to the ident branch), then a reputed user
approves via `like author <key>` which merges everything.

## Design decisions

- Trailer: `Freechains: ident`
- Command: `freechains chain <alias> ident [<bio.md>]
  [--why=...] --sign <KEY>`
- Optional positional `<bio.md>`: free-form markdown bio
  (links, description, etc) stored at
  `.freechains/id/<KEY>.md` (outside `state/`, normal merge)
- One-shot: bio updates not supported yet
- GPG pubkey auto-extracted from GNUPGHOME
- Approval: `like N author <KEY>` (not `like N post <hash>`)
- Off-main branch: `refs/idents/ident-<KEY>` (keyed by
  identity, not hash — one ident per key)
- Merged into main when approved via like

## Approval flow

1. User runs `ident [bio.md] --sign <KEY>`
   - Extracts pubkey from GNUPGHOME
   - Writes `.freechains/keys/<KEY>.asc`
   - If bio provided: copies to `.freechains/id/<KEY>.md`
   - Signs commit with trailer `Freechains: ident`
   - State commit follows
   - Creates `refs/idents/ident-<KEY>`, HEAD reset
2. User runs `post --sign <KEY>` (one or more times)
   - Detects author has reps <= 0 and ident ref exists
   - Checks out ident branch, posts there, switches back
   - Content accumulates on the ident branch
3. Pioneer runs `like N author <KEY>`
   - Detects `refs/idents/ident-<KEY>` exists
   - Merges entire ident branch (key + posts) into main
   - Author receives reputation via like
   - All posts transition from `blocked` to `00-12`
   - Ident ref deleted
4. User can now post normally on main with `--sign <KEY>`

## Two user paths

### Freechains-aware (CLI)

Uses `ident` → `post` → `like author` flow with trailers.
Explicit, structured, ident branch mechanism.

### Git-native (unaware of freechains)

Plain `git commit` (signed or unsigned), no trailers.
During sync replay, commits without trailers are handled:

| Commit          | Key known? | Action                          |
|-----------------|------------|---------------------------------|
| Signed, known   | yes        | Normal post, deduct reps        |
| Signed, unknown | no         | Auto-register (reps=0), blocked |
| Unsigned        | —          | Beg (blocked)                   |

Auto-register: if sync encounters a signed commit from an
unknown key, it creates an implicit ident entry
(`G.authors[key] = { reps=0 }`) and the post is blocked.
Approval still requires `like author <KEY>` from a reputed
user.

This preserves compatibility with plain git workflows.

## Key difference from old beg-like

Old: `like N post <beg-hash>` — targets the post entry.
New: `like N author <KEY>` — targets the author directly.
The like-on-author path already exists (`common.lua:148-151`)
but needs adaptation to handle ident branch merging.

## Implementation steps

### 1. Create `src/freechains/chain/ident.lua`

New file. Structure mirrors `post.lua`:

```
-- validate: --sign required, author must not have reps > 0
-- extract pubkey: gpg --export --armor <KEY>
-- write .freechains/keys/<KEY>.asc
-- git add + signed commit with trailer 'Freechains: ident'
-- apply(G, 'ident', ...)
-- write state + state commit
-- create ref: refs/idents/ident-<KEY>
-- reset HEAD back 2
-- print hash
```

For GPG pubkey extraction:
```
gpg --export --armor <KEY>
```
Strip PGP headers, store base64 body only, then write
`.asc` file wrapping it (same as `pioneers()` in
`chains.lua`).

### 2. Add `'ident'` kind to `apply()` in `common.lua`

After the `'post'` branch (~line 118), add:

```lua
elseif kind == 'ident' then
    if G.authors[T.sign] and G.authors[T.sign].reps > 0 then
        return false, "already registered"
    end
    G.authors[T.sign] = G.authors[T.sign] or { reps=0 }
```

No G.posts entry needed — ident is not a post.
No reputation deducted (they have none).

### 3. Adapt `like.lua` for ident approval

When `target == "author"`:
- Check if `refs/idents/ident-<ARGS.id>` exists
- If yes: merge ident branch into main
- Replay ident branch posts into G (they were off-main)
- Transition all blocked posts from that author to `'00-12'`
- Delete ident ref after commit
- The existing `apply(G, 'like', ...)` author path handles
  the rep transfer unchanged

Replace `refs/begs/beg-` → `refs/idents/ident-`.
Rename `to_beg` → `to_ident`.
Detection: `refs/idents/ident-<ARGS.id>` where `ARGS.id`
is the author key.

### 4. Adapt `post.lua` for ident branch

Remove `--beg` flag. Post now has two modes:

**Reputed author (reps > 0):** unchanged, posts on main.

**Unreputed author (reps <= 0):**
- Check `refs/idents/ident-<KEY>` exists, else error
  ("run ident first")
- Checkout ident branch
- Post content there (same git add + commit + state)
- Update ident ref to new HEAD
- Checkout main

```
-- detect ident branch
local ref = "refs/idents/ident-" .. ARGS.sign
local on_ident = (reps <= 0) and exec(true,
    "git -C " .. REPO ..
    " rev-parse --verify " .. ref)

if reps <= 0 and not on_ident then
    ERROR("chain post : run ident first")
end

if on_ident then
    exec("git -C " .. REPO .. " checkout " .. ref)
    -- ... post content + state ...
    exec("git -C " .. REPO ..
        " update-ref " .. ref .. " HEAD")
    exec("git -C " .. REPO .. " checkout main")
else
    -- ... normal post on main ...
end
```

Posts on ident branch use `state = 'blocked'` (same as
old beg). They transition to `'00-12'` when the like
merges them into main.

### 5. Adapt beg logic in `apply()` in `common.lua`

Replace `T.beg` with `T.ident` flag:

- Line 95: `if T.sign and not T.ident` → check reps
- Line 106: `T.ident and 'blocked'` or `'00-12'`
- Lines 111-116: `if not T.ident` → deduct cost
- Lines 144-147: keep unblock logic but trigger on
  `T.ident` instead of `T.beg` — when like merges ident
  branch, all blocked posts transition to `'00-12'`

### 6. Add CLI command in `freechains.lua`

In `cmd.chain` table (~line 46): add `ident = {}`

After cmd.chain.sync block (~line 139):
```lua
cmd.chain.ident._ = cmd.chain._:command("ident")
cmd.chain.ident._:argument("bio"):args("?")
cmd.chain.ident._:option("--sign")
cmd.chain.ident._:option("--why")
```

Remove line 90: `cmd.chain.post._:flag("--beg")`

### 7. Add dispatch in `chain/init.lua`

After `ARGS.like or ARGS.dislike` block (~line 25):
```lua
elseif ARGS.ident then
    require "freechains.chain.ident"
```

### 8. Update `sync.lua` replay

Add `"ident"` trailer in `replay()` (~line 69):
```lua
elseif trailer == "ident" then
    local ok, err = apply(G, 'ident', tonumber(time), {
        sign = key,
    })
```

**Git-native path (no trailer):**

For commits without a freechains trailer (plain git
commits), add a fallback branch:
```lua
elseif trailer == "" then
    -- git-native user, no freechains trailer
    local ident = (key and not G.authors[key])
    local beg = (key == nil)
    if ident then
        -- auto-register unknown signer
        G.authors[key] = { reps=0 }
    end
    local ok, err = apply(G, 'post', tonumber(time), {
        hash  = hash,
        sign  = key,
        ident = (ident or beg),
    })
```

This handles:
- Signed, unknown key → auto-register + blocked post
- Signed, known key → normal post (deduct reps)
- Unsigned → beg (blocked post)

### 9. Rewrite tests

| Old file                    | New file                     |
|-----------------------------|------------------------------|
| `tst/cli-begs.lua`         | `tst/cli-idents.lua`         |
| `tst/repl-local-begs.lua`  | `tst/repl-local-idents.lua`  |
| `tst/repl-remote-begs.lua` | `tst/repl-remote-idents.lua` |

Key changes in tests:
- `--beg --sign` → `ident --sign` + `post --sign`
- `refs/begs/` → `refs/idents/`
- Like targets `author <KEY>` not `post <hash>`
- Ident commit has keyring files, post commits have content
- Flow: ident → post(s) → like author

## Files

| File                              | Action |
|-----------------------------------|--------|
| `src/freechains/chain/ident.lua`  | CREATE |
| `src/freechains/chain/common.lua` | MODIFY |
| `src/freechains/chain/post.lua`   | MODIFY |
| `src/freechains/chain/like.lua`   | MODIFY |
| `src/freechains/chain/sync.lua`   | MODIFY |
| `src/freechains/chain/init.lua`   | MODIFY |
| `src/freechains.lua`              | MODIFY |
| `tst/cli-begs.lua`               | RENAME |
| `tst/repl-local-begs.lua`        | RENAME |
| `tst/repl-remote-begs.lua`       | RENAME |

## Open questions

1. **GEN_0 chains (no pioneers)**: nobody can approve idents.
   Same limitation as old begs. Tests only verify git
   mechanics, not approval flow.

2. **SSH ident**: same flow but writes to `allowed_signers`
   instead of `.asc`. Key type detected from format
   (40 hex → GPG, `ssh-*` prefix → SSH).

## Verification

```
cd tst
GNUPGHOME=$(realpath gnupg/) lua5.4 cli-idents.lua
GNUPGHOME=$(realpath gnupg/) lua5.4 repl-local-idents.lua
GNUPGHOME=$(realpath gnupg/) lua5.4 repl-remote-idents.lua
GNUPGHOME=$(realpath gnupg/) lua5.4 cli-sign.lua
GNUPGHOME=$(realpath gnupg/) lua5.4 cli-like.lua
```
