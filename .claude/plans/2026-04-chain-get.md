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

Acceptance differs by command:

| Command   | Accepts     | Rejects                       |
|-----------|-------------|-------------------------------|
| `block`   | post, like  | state, genesis (no payload concept) |
| `payload` | post        | like, state, genesis           |

All rejection cases share the single error `ERROR : chain get : unknown post`
(this also covers an unknown/invalid hash — collapsed into the same error).

## Status

In progress.

| Step | Item                                                | State    |
|------|-----------------------------------------------------|----------|
| 0    | `tst/cli-get.lua` (test file)                       | needs rework — 10 cases per Tests table |
| 1    | CLI parse in `src/freechains.lua`                   | done     |
| 2    | dispatch in `src/freechains/chain/init.lua`         | done     |
| 3a   | `src/freechains/chain/get.lua` — payload + scaffolding + block-TODO | this iteration |
| 3b   | `src/freechains/chain/get.lua` — block branch implementation        | deferred       |
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
| `like`       | table or `false`    | for `like` commits: `{ n=<raw number>, target="post"|"author", id=<hash-or-pubkey> }`; for posts: `false` |
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

Unified rejection error: `ERROR : chain get : unknown post`.

| Trigger                                            | Command  | Result        |
|----------------------------------------------------|----------|---------------|
| `<hash>` does not exist                            | both     | unknown post  |
| `<hash>` trailer is `state` (incl. genesis)        | both     | unknown post  |
| `<hash>` trailer is `like`                         | payload  | unknown post  |
| `<hash>` trailer is `like`                         | block    | (accepted)    |
| `<hash>` trailer is `post`                         | both     | (accepted)    |

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

Setup: GEN_2 (file genesis, two pioneers); KEY1 posts `'hello world'` (→ `POST`);
KEY2 likes the post (→ `LIKE`). `STATE = HEAD`, `GENESIS = git rev-list --max-parents=0`.

| #  | Case                          | Expected                                          |
|----|-------------------------------|---------------------------------------------------|
| 1  | `payload <post>`              | output == `"hello world"`                         |
| 2  | `payload <like>`              | exit 1, `ERROR : chain get : unknown post`        |
| 3  | `payload <state>`             | exit 1, `ERROR : chain get : unknown post`        |
| 4  | `payload <genesis>`           | exit 1, `ERROR : chain get : unknown post`        |
| 5  | `payload <unknown-hash>`      | exit 1, `ERROR : chain get : unknown post`        |
| 6  | `block <post>`                | exit 1, `ERROR : chain get : TODO block`          |
| 7  | `block <like>`                | exit 1, `ERROR : chain get : TODO block`          |
| 8  | `block <state>`               | exit 1, `ERROR : chain get : unknown post`        |
| 9  | `block <genesis>`             | exit 1, `ERROR : chain get : unknown post`        |
| 10 | `block <unknown-hash>`        | exit 1, `ERROR : chain get : unknown post`        |

## Errors (per `.claude/CLAUDE.md` format)

```
ERROR : chain get : unknown post
ERROR : chain get : TODO block       -- temporary, until block branch is implemented
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

This iteration: `payload` is implemented; `block` errors with TODO.

```lua
require "freechains.chain.common"

-- existence + chain-membership in one shot: HEAD-reachability.
-- rejects: any non-commit object, dangling commits, beg-only refs,
-- forged objects from sync attacks.
do
    local _, code = exec(true, 'stdout',
        "git -C " .. REPO .. " merge-base --is-ancestor " .. ARGS.hash .. " HEAD"
    )
    if code ~= 0 then
        ERROR("chain get : unknown post")
    end
end

local kind = trailer(ARGS.hash)

if ARGS.payload then
    if kind ~= "post" then
        ERROR("chain get : unknown post")
    else
        -- continue
    end
    local files = exec (
        "git -C " .. REPO ..
        " diff-tree --no-commit-id -r --name-only " .. ARGS.hash
    )
    local file = files:match("^(%S+)")
    local out = exec (
        "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file
    )
    io.write(out)

elseif ARGS.block then
    if kind ~= "post" and kind ~= "like" then
        ERROR("chain get : unknown post")
    else
        -- continue
    end
    ERROR("chain get : TODO block")
end
```

Future block branch (deferred): builds Lua table per the
"`get block` → Lua table" spec above. Like-file format
(from `chain/like.lua`):

```lua
return { target = "post"|"author", id = "<id>", number = ±N*reps.unit }
```

Will map 1:1 to `like = { n=number, target=target, id=id }`.

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
| H | `like` shape                                          | `{ n, target, id }` — `n` = raw `number` from like file (no rescaling by `C.reps.unit`) |

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
