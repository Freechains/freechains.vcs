# Query: Raw Data Access via CLI

## Overview

A generic `query` subcommand that returns raw internal
state as Lua tables (`return {...}`).
No processing, no `ext()` conversion — just the data.

Users and programs should access `.freechains/` data
exclusively through the CLI API.

## Commands

| Command          | Source                          | Returns                      |
|------------------|---------------------------------|------------------------------|
| `query authors`  | `.freechains/authors.lua`       | pubkey → { reps, time }     |
| `query posts`    | `.freechains/posts.lua`         | blob → { reps, author, ... }|
| `query genesis`  | `.freechains/genesis.lua`       | chain config table           |
| `query likes`    | `.freechains/likes/*.lua`       | merged table of all likes    |

All return `return {...}` format, suitable for
`load()` or `dofile()` by Lua programs.

## Details

### query authors

Returns the full `authors.lua` content after time
effects (stage scan).
Includes all pioneers and all signing authors.

```lua
return {
    ["CA6391CE..."] = { reps=29000, time=1710374400 },
    ["78397501..."] = { reps=900 },
}
```

### query posts

Returns the full `posts.lua` content after time
effects (stage scan).
Includes all created posts.

```lua
return {
    ["a1b2c3d4..."] = { reps=0, author="CA6391CE...", time=0, state="00-12" },
    ["e5f6g7h8..."] = { reps=1350, author="CA6391CE..." },
}
```

### query genesis

Returns the genesis config table.

```lua
return {
    version = {1, 2, 3},
    type    = "#",
    name    = "A forum",
    descr   = "This forum is about...",
}
```

### query likes

Scans all `.freechains/likes/*.lua` files and returns
a merged table keyed by filename.

```lua
return {
    ["like-1710288000-a1b2c3d4.lua"] = {
        target = "post",
        id     = "a1b2c3d4...",
        number = 1000,
    },
}
```

## Relationship with `reps` command

When `query` is implemented, the current `reps` commands
will be replaced:
- `reps author <key>` → use `query authors` + extract
- `reps post <hash>` → use `query posts` + extract
- `reps authors` → use `query authors`
- `reps posts` → use `query posts`

All `reps` subcommands (author, post, authors, posts)
will be removed in favor of `query`.

## Open Questions

1. Should `query likes` return an array or a map keyed
   by filename?
2. Should `query` run the stage scan (time effects)
   before returning, or return committed state only?

## Files to Modify

| File                      | Changes                             |
|---------------------------|-------------------------------------|
| `src/freechains.lua`      | Add `query` subcommand to argparse  |
| `src/freechains/chain.lua`| Add `query` handler                 |
| `tst/cli-query.lua`       | New test file                       |

## TODO

- [ ] Add `query` subcommand to argparse
- [ ] Impl: query authors
- [ ] Impl: query posts
- [ ] Impl: query genesis
- [ ] Impl: query likes
- [ ] Tests: all query variants
