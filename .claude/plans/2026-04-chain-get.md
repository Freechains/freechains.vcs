# Plan: `chain get block` / `chain get payload`

## Goal

Add a `chain <alias> get` command with two variants, mirroring
the Kotlin Freechains:

```
freechains chain <alias> get block   <hash>
freechains chain <alias> get payload <hash>
```

| Variant   | Output                                              |
|-----------|-----------------------------------------------------|
| `block`   | Lua table mirroring Kotlin `Block_Get`              |
|           | (`hash`, `time`, `pay`, `like`, `sign`, `backs`)    |
| `payload` | the file content added by the post commit           |

Both variants accept `post` and `like` trailer commits.
`state` (and genesis) commits are rejected with `unknown post`.

## Status

In progress.

| Step | Item                                                | State    |
|------|-----------------------------------------------------|----------|
| 0    | `tst/cli-get.lua` (test file)                       | needs rework — assertions for new Lua-table output and "unknown post" error |
| 1    | CLI parse in `src/freechains.lua`                   | done     |
| 2    | dispatch in `src/freechains/chain/init.lua`         | done     |
| 3    | `src/freechains/chain/get.lua` (implementation)     | needs rework — Lua-table output, single "unknown post" reject |
| 4    | rockspec module entry                               | pending  |
| 5    | `Makefile` test line                                | pending  |
| 6    | README Step 8 walkthrough                           | pending  |
| 7    | `.claude/plans/commands.md` rows                    | pending  |

## CLI

| Form                                            | Behavior                                  |
|-------------------------------------------------|-------------------------------------------|
| `chain <alias> get block <hash>`                | print Lua-table view of the commit         |
| `chain <alias> get payload <hash>`              | print the file added by `<hash>`           |

No flags, no `--sign` (read-only command).

## Reference: Kotlin `Block_Get`

Source: `/x/freechains/kt/src/main/kotlin/org/freechains/host/Block.kt`
lines 38-46; constructed in `Daemon.kt:298-308`.

```kotlin
data class Block_Get (
    val hash   : Hash,
    val time   : Long,
    val pay    : Payload,     // { crypt: Boolean, hash: Hash }
    val like   : Like?,       // { n: Int, hash: Hash }
    val sign   : Signature?,  // { hash: String, pub: HKey }
    val backs  : Set<Hash>
)
```

Kotlin returns this serialized as JSON. Error on missing block:
`"! block not found"`.

## Mapping to git (Lua port)

### `get block` → Lua table

| Field        | Type                | Source                                                            |
|--------------|---------------------|-------------------------------------------------------------------|
| `hash`       | string              | the commit hash itself (40-hex)                                   |
| `time`       | integer             | `git log -1 --format=%at <hash>` (author epoch)                   |
| `pay.hash`   | string              | `git ls-tree <hash> <file>` blob hash                             |
| `like`       | table or `false`    | for `like` commits: `{ n=±N, hash=<target> }`; for posts: `false` |
| `sign`       | table or `false`    | signed: `{ hash=<sshsig-body-b64>, pub="ssh-ed25519 <b64>" }`; unsigned: `false` |
| `backs`      | array of string     | parents from `git rev-list --parents -n 1 <hash>`                 |

`pay.crypt` is omitted (always `false` in lua port).

Output via `serial()` (project helper) — produces loadable Lua source.

Accepted trailers: `post`, `like`.
Otherwise → `ERROR : chain get : unknown post`.

### `get payload`

Same trailer reject as `block` (accepts `post` and `like`,
rejects `state`).
Then two-step git extraction:

1. Find the file added by the commit:

   ```
   git -C <repo> diff-tree --no-commit-id -r --name-only <hash>
   ```

   A `post` commit yields exactly one file (the user payload).
   A `like` commit yields `.freechains/likes/like-*.lua`.

2. Print its content:

   ```
   git -C <repo> show <hash>:<file>
   ```

## Validation

Single check applies to both `block` and `payload`:

| Trigger                                                  | Error                                  |
|----------------------------------------------------------|----------------------------------------|
| `<hash>` not in repo                                     | `ERROR : chain get : invalid hash`     |
| `<hash>` trailer is `state` (covers state + genesis)     | `ERROR : chain get : unknown post`     |

Accepted trailers: `post`, `like`.

## Files to modify

| File                              | Place                          | Change                                                                                                  |
|-----------------------------------|--------------------------------|---------------------------------------------------------------------------------------------------------|
| `src/freechains.lua`              | `cmd.chain` block              | add `get` subcommand with two children: `block` and `payload`, each takes positional `hash`             |
| `src/freechains.lua`              | dispatch                       | nothing — `freechains.chain` init.lua already does require dispatch                                     |
| `src/freechains/chain/init.lua`   | dispatch chain                 | add `elseif ARGS.get then require "freechains.chain.get"`                                               |
| `src/freechains/chain/get.lua`    | new file                       | `if ARGS.block then ... elseif ARGS.payload then ... end`                                               |
| `freechains-0.20-1.rockspec`      | `build.modules`                | add `["freechains.chain.get"] = "src/freechains/chain/get.lua"`                                         |
| `tst/cli-get.lua`                 | new file                       | tests: block of post, block of genesis, payload of post (text), payload of state errors, invalid hash    |
| `Makefile`                        | `tests` target                 | add `$(L) cli-get.lua` line                                                                             |
| `README.md`                       | walkthrough Step 8             | replace pending `ls + cat` snippet with `chain get payload <hash>`                                      |
| `.claude/plans/commands.md`       | row mapping                    | add `chain get block` and `chain get payload` rows (currently absent)                                   |

## Tests (`tst/cli-get.lua`)

| #  | Case                                       | Expected                                                                                                                |
|----|--------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| 1  | `get block <post-hash>`                    | loadable Lua: `hash`, `time`, `pay.hash` (40-hex), `like == false`, `sign.pub` starts with `ssh-ed25519 `, `backs` array |
| 2  | `get block <genesis-hash>`                 | exit 1, `ERROR : chain get : unknown post`                                                                              |
| 3  | `get block <state-hash>`                   | exit 1, `ERROR : chain get : unknown post`                                                                              |
| 4  | `get block <like-hash>`                    | loadable Lua: `like.n` integer, `like.hash` is the target post hash                                                     |
| 5  | `get payload <post-hash>`                  | output equals the original posted text                                                                                  |
| 6  | `get payload <genesis-hash>`               | exit 1, `ERROR : chain get : unknown post`                                                                              |
| 7  | `get payload <state-hash>`                 | exit 1, `ERROR : chain get : unknown post`                                                                              |
| 8  | `get payload <like-hash>`                  | output is the like Lua source                                                                                           |
| 9  | `get block <unknown-hash>`                 | exit 1, `ERROR : chain get : invalid hash`                                                                              |
| 10 | `get payload <unknown-hash>`               | exit 1, `ERROR : chain get : invalid hash`                                                                              |

## Errors (per `.claude/CLAUDE.md` format)

```
ERROR : chain get : invalid hash
ERROR : chain get : unknown post
```

## README impact

Step 8 walkthrough becomes:

````markdown
- Read post payloads:

```
freechains chain '#chat' get payload b52c62f...
Hello World!
freechains chain '#chat' get payload d6568e4...
I am here!
```

For the structured block view (post):

```
freechains chain '#chat' get block b52c62f...
return {
    ["backs"] = { "<parent-hash>", },
    ["hash"]  = "b52c62f...",
    ["like"]  = false,
    ["pay"]   = {
        ["hash"] = "<blob-hash>",
    },
    ["sign"]  = {
        ["hash"] = "<sshsig-b64>",
        ["pub"]  = "ssh-ed25519 ...",
    },
    ["time"]  = 1714560000,
}
```
````

## Implementation sketch — `chain/get.lua`

```lua
require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

-- existence check
local function exists (hash)
    local _, code = exec(true, 'stdout',
        "git -C " .. REPO .. " cat-file -e " .. hash
    )
    return code == 0
end

if not exists(ARGS.hash) then
    ERROR("chain get : invalid hash")
else
    -- continue
end

-- trailer check (accept post/like, reject state)
local kind = trailer(ARGS.hash)
if kind ~= "post" and kind ~= "like" then
    ERROR("chain get : unknown post")
else
    -- continue
end

-- find the single tracked file (one for post, one for like)
local function payfile ()
    local files = exec (
        "git -C " .. REPO ..
        " diff-tree --no-commit-id -r --name-only " .. ARGS.hash
    )
    return files:match("^(%S+)")
end

if ARGS.block then
    local file = payfile()

    -- pay.hash: blob hash from ls-tree
    local blob = exec (
        "git -C " .. REPO .. " ls-tree " .. ARGS.hash .. " " .. file
    ):match("^%S+%s+%S+%s+(%S+)")

    -- backs: parents
    local backs = {}
    local raw = exec (
        "git -C " .. REPO .. " rev-list --parents -n 1 " .. ARGS.hash
    )
    local first = true
    for h in raw:gmatch("%S+") do
        if first then
            first = false
        else
            backs[#backs+1] = h
        end
    end

    -- sign: pubkey via ssh helper, raw sshsig body via gpgsig parse
    local sign = false
    local pub = ssh.pubkey(REPO, ARGS.hash)
    if pub then
        local commit = exec (
            "git -C " .. REPO .. " cat-file commit " .. ARGS.hash
        )
        local body = ""
        local in_sig = false
        for line in (commit .. "\n"):gmatch("([^\n]*)\n") do
            if in_sig then
                if line:sub(1,1) == " " then
                    local s = line:sub(2)
                    if not s:match("^%-%-%-") then
                        body = body .. s
                    else
                        -- skip armor
                    end
                else
                    in_sig = false
                end
            else
                if line:match("^gpgsig ") then
                    in_sig = true
                else
                    -- skip
                end
            end
        end
        sign = { hash = body, pub = pub }
    else
        -- unsigned
    end

    -- like: only for like-trailer commits
    local like = false
    if kind == "like" then
        local content = exec (
            "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file
        )
        local L = load(content, "like", "t", {})()
        like = { n = L.n, hash = L.hash }
    else
        -- post: like stays false
    end

    local T = {
        hash  = ARGS.hash,
        time  = tonumber(exec (
            "git -C " .. REPO .. " log -1 --format=%at " .. ARGS.hash
        )),
        pay   = { hash = blob },
        like  = like,
        sign  = sign,
        backs = backs,
    }
    io.write(serial(T))

elseif ARGS.payload then
    local file = payfile()
    local out = exec (
        "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file
    )
    io.write(out)
end
```

Helpers: `trailer()` from `chain.common`, `serial()` from `freechains.common`,
`ssh.pubkey()` from `chain.ssh`.

Open: confirm the format of `.freechains/likes/like-*.lua` so
the `like` extraction loads `n` and `hash` correctly. Need to
inspect `chain/like.lua`.

## Decisions (locked)

| # | Question                                              | Choice                                 |
|---|-------------------------------------------------------|----------------------------------------|
| A | Output format                                         | `serial()` (Lua source)                |
| B | `like` field                                          | keep — populated for like commits, present-but-absent marker for posts |
| C | `pay.crypt` field                                     | omit                                   |
| D | `backs` shape                                         | array                                  |
| E | `sign` when unsigned                                  | present-but-absent marker              |
| F | `sign.hash` content                                   | raw base64 SSHSIG body (no armor)      |
| G | Short hash acceptance                                 | accept (git resolves)                  |

### Absence representation

Lua tables cannot store `nil` values, and project's `serial()` helper
omits absent keys. Per user requirement *"nil values should not be
omitted"*, absent fields are rendered using a sentinel.

**Marker: `false`** (renders as `["like"] = false` in `serial()`).

Applies to:

| Field   | Value when absent                                |
|---------|--------------------------------------------------|
| `like`  | `false` for `post`-trailer commits               |
| `sign`  | `false` for unsigned commits                     |

### Consequence

`block` and `payload` accept both `post` and `like` trailer commits.
Only `state` (incl. genesis) is rejected with `unknown post`.

## Out of scope

- A `chain get all` or `chain get heads` listing.
- JSON output. Lua-table output is the chosen format.
- Non-post payloads in a structured form.
