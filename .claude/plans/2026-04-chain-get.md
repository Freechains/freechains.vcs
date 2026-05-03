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
| 3a   | `src/freechains/chain/get.lua` — payload + scaffolding + block-TODO | done           |
| 3b   | `src/freechains/chain/get.lua` — block branch implementation        | done           |
| 3c   | `src/freechains/chain/ssh.lua` — `M.gpgsig` helper                  | reverted (sign field is scalar pubkey only — proof dropped) |
| 4    | rockspec module entry                               | pending  |
| 5    | `Makefile` test line                                | pending  |
| 6    | README Step 8 walkthrough                           | pending  |
| 7    | `.claude/plans/commands.md` rows                    | pending  |
| 8    | unsigned-post block test (validates `sign = false`) | pending  |

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
| `post`       | table or `false`    | for `post` commits: `{ file=<path>, hash=<blob-hash> }`; for likes: `false` |
| `like`       | table or `false`    | for `like` commits: see §like-shape (separate plan `2026-05-like-shape.md`); for posts: `false` |
| `sign`       | string or `false`   | signed: `"ssh-ed25519 <b64>"`; unsigned: `false` (raw signature still recoverable from `git cat-file commit <hash>` if needed) |
| `backs`      | array of string     | parents from `git rev-list --parents -n 1 <hash>` (skip self)     |
| `why`        | string              | `git log -1 --format=%B <hash>` minus trailing `Freechains: <kind>` line |

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
| 6  | `block <post>`                | exit 0; loadable Lua: `hash`, `time` int, `pay.hash` 40-hex, `like == false`, `sign.pub` matches `ssh-ed25519 `, `backs` array len 1 |
| 7  | `block <like>`                | exit 0; loadable Lua: `like.target == "post"`, `like.id == POST`, `like.n` int |
| 8  | `block <state>`               | exit 1, `ERROR : chain get : unknown post`        |
| 9  | `block <genesis>`             | exit 1, `ERROR : chain get : unknown post`        |
| 10 | `block <unknown-hash>`        | exit 1, `ERROR : chain get : unknown post`        |
| 11 | `block <unsigned-post>`       | exit 0; loadable Lua: `T.sign == false`, `type(T.post) == "table"` |

Setup for case 11: create an unsigned commit directly via raw git
(not through `chain post`), with `Freechains: post` trailer:

```lua
local f = io.open(DIR .. "unsigned.txt", "w")
f:write("unsigned content\n")
f:close()
exec("git -C " .. DIR .. " add unsigned.txt")
exec("git -C " .. DIR .. " commit -m '(empty message)' --trailer 'Freechains: post'")
local UNSIGNED = exec("git -C " .. DIR .. " rev-parse HEAD")
```

This bypasses `chain post`'s `--sign` requirement so the commit
ends up signed by no key (no `gpgsig` header). Reachable from
HEAD → `merge-base --is-ancestor` accepts.

## Errors (per `.claude/CLAUDE.md` format)

```
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
    ["sign"]  = "ssh-ed25519 ...",
    ["time"]  = 1714560000,
    ["why"]   = "(empty message)",
}
```
````

## Implementation summary — `chain/get.lua`

- existence: `git merge-base --is-ancestor <hash> HEAD` (rejects any non-chain object: trees, blobs, dangling commits, beg-only refs, forged objects).
- trailer: read once via `trailer(<hash>)`, then per-branch reject.
- `payload` accepts `post` only; `block` accepts `post` and `like`.
- block table fields built from:
  - `pay.hash`  — `git ls-tree <hash> <file>` (3rd column)
  - `backs`     — `git rev-list --parents -n 1 <hash>` (drop self)
  - `sign`      — `ssh.pubkey(REPO, hash)` (string) or `nil` if unsigned (key omitted)
  - `like`      — for `like` commits: `load(<file content>)()` then map `{n=L.number, target=L.target, id=L.id}`; `false` for posts
  - `why`       — `git log -1 --format=%B` minus trailing `Freechains: <kind>` line
  - `time`      — `git log -1 --format=%at`
  - `hash`      — `ARGS.hash`

Output via `serial(T)`.

No change to `ssh.lua` — only `M.pubkey` is consumed.

## Decisions (locked)

| # | Question                                              | Choice                                 |
|---|-------------------------------------------------------|----------------------------------------|
| A | Output format                                         | `serial()` (Lua source)                |
| B | `like` field                                          | keep — populated for like commits, present-but-absent marker for posts |
| C | `pay.crypt` field                                     | omit                                   |
| D | `backs` shape                                         | array                                  |
| E | `sign` when unsigned                                  | `false` sentinel (uniform with other absent fields; rendered in output) |
| F | `sign` shape                                          | scalar string `"ssh-ed25519 <b64>"` or `false` (was `{hash, pub}`; proof dropped — already in `gpgsig` header) |
| G | Short hash acceptance                                 | accept (git resolves)                  |
| H | `like` shape                                          | `{ n, target, id }` — `n` = raw `number` from like file (no rescaling by `C.reps.unit`) |

### Absence representation

Lua tables cannot store `nil` values; `serial()` omits absent keys.
To force every potentially-absent field to render in the output,
**all** absence is represented by the `false` sentinel.

| Field   | Absent value | When                                |
|---------|--------------|-------------------------------------|
| `post`  | `false`      | for `like`-trailer commits          |
| `like`  | `false`      | for `post`-trailer commits          |
| `sign`  | `false`      | for unsigned commits                |

Each renders as `["foo"] = false` in `serial()` output and is
explicit at the consumer: presence of a *table* discriminates the
record kind (post vs like) or the signed/unsigned status.

### Consequence

`block` and `payload` accept both `post` and `like` trailer commits.
Only `state` (incl. genesis) is rejected with `unknown post`.

## Out of scope

- A `chain get all` or `chain get heads` listing.
- JSON output. Lua-table output is the chosen format.
- Non-post payloads in a structured form.
