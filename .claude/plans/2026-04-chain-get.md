# Plan: `chain get block` / `chain get payload`

## Goal

Add a `chain <alias> get` command with two variants, mirroring
the Kotlin Freechains:

```
freechains chain <alias> get block   <hash>
freechains chain <alias> get payload <hash>
```

| Variant   | Output                                            |
|-----------|---------------------------------------------------|
| `block`   | raw git commit object (tree, parents, author,     |
|           | committer, message, `gpgsig`, `Freechains:` trailer) |
| `payload` | the file content added by the post commit         |

## Status

In progress.

| Step | Item                                                | State    |
|------|-----------------------------------------------------|----------|
| 0    | `tst/cli-get.lua` (test file)                       | done     |
| 1    | CLI parse in `src/freechains.lua`                   | done     |
| 2    | dispatch in `src/freechains/chain/init.lua`         | done     |
| 3    | `src/freechains/chain/get.lua` (implementation)     | done     |
| 4    | rockspec module entry                               | pending  |
| 5    | `Makefile` test line                                | pending  |
| 6    | README Step 8 walkthrough                           | pending  |
| 7    | `.claude/plans/commands.md` rows                    | pending  |

## CLI

| Form                                            | Behavior                                  |
|-------------------------------------------------|-------------------------------------------|
| `chain <alias> get block <hash>`                | print `git cat-file commit <hash>` output |
| `chain <alias> get payload <hash>`              | print the file added by `<hash>`           |

No flags, no `--sign` (read-only command).

## Mapping to git

### `get block`

```
git -C <repo> cat-file commit <hash>
```

Output is the raw commit object (text, not pretty-printed).
Includes `gpgsig` SSHSIG block when the commit is signed.
Works for any commit reachable from the chain (genesis, posts,
likes, state).

### `get payload`

Two-step:

1. Find the file added by the commit:

   ```
   git -C <repo> diff-tree --no-commit-id -r --name-only <hash>
   ```

   For a `post` commit this yields exactly one file (matching
   `post.lua` which calls `git add <file>` for the single payload).
   For a `like` commit it yields a single
   `.freechains/likes/like-*.lua`.
   For a `state` commit it yields the `.freechains/state/*` files
   — payload semantics are undefined; error.

2. Print its content:

   ```
   git -C <repo> show <hash>:<file>
   ```

## Validation

| Trigger                                              | Error                                              |
|------------------------------------------------------|----------------------------------------------------|
| `<hash>` not in repo                                 | `ERROR : chain get : invalid hash`                 |
| `<hash>` is a state commit (for `payload`)           | `ERROR : chain get : no payload`                   |
| `<hash>` is the genesis (for `payload`)              | `ERROR : chain get : no payload`                   |
| Commit adds zero files or more than one (for `payload`) | `ERROR : chain get : no payload`                |

`block` accepts any reachable commit, no validation beyond
existence.

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

| #  | Case                                            | Expected                                              |
|----|-------------------------------------------------|-------------------------------------------------------|
| 1  | `get block <post-hash>`                         | output contains `tree`, `parent`, `Freechains: post`  |
| 2  | `get block <genesis-hash>`                      | output contains `tree`, no `parent`, `Freechains: state` |
| 3  | `get payload <post-hash>`                       | output equals the original posted text                |
| 4  | `get payload <genesis-hash>`                    | exit 1, `ERROR : chain get : no payload`              |
| 5  | `get payload <state-hash>`                      | exit 1, `ERROR : chain get : no payload`              |
| 6  | `get block <unknown-hash>`                      | exit 1, `ERROR : chain get : invalid hash`            |
| 7  | `get payload <like-hash>` (deferred)            | currently: emits the like Lua source. Decide: error or allow? |

## Errors (per `.claude/CLAUDE.md` format)

```
ERROR : chain get : invalid hash
ERROR : chain get : no payload
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

For the raw block (commit object, signature, trailer):

```
freechains chain '#chat' get block b52c62f...
tree ...
parent ...
author -  <-> ...
...
Freechains: post
```
````

## Implementation sketch — `chain/get.lua`

```lua
require "freechains.chain.common"

local function exists (hash)
    local _, code = exec(true, 'stdout',
        "git -C " .. REPO .. " cat-file -e " .. hash
    )
    return code == 0
end

if not exists(ARGS.hash) then
    ERROR("chain get : invalid hash")
end

if ARGS.block then
    local out = exec(
        "git -C " .. REPO .. " cat-file commit " .. ARGS.hash
    )
    io.write(out)

elseif ARGS.payload then
    local kind = trailer(ARGS.hash)
    if kind == "state" then
        ERROR("chain get : no payload")
    end
    local files = exec(
        "git -C " .. REPO ..
        " diff-tree --no-commit-id -r --name-only " .. ARGS.hash
    )
    -- expect exactly one file
    local file = files:match("^(%S+)\n?$")
    if not file then
        ERROR("chain get : no payload")
    end
    local out = exec(
        "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file
    )
    io.write(out)
end
```

`trailer()` is the helper now in `chain/common.lua`.

## Open questions

- `payload` for `like` commits: emit raw Lua, or treat as
  "no payload"? Default: emit (it's the like's metadata file).
  Tests may need adjustment.
- Should `get` accept a short hash (`b52c62f`) or only full
  hashes? Defer — git commands accept either, no extra work.

## Out of scope

- A `chain get all` or `chain get heads` listing.
- JSON output. Raw git output is fine; users can pipe to tools.
- Non-post payloads in a structured form.
