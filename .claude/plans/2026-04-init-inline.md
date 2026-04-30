# Plan: `chains add ... init inline`

## Goal

Split `freechains chains add <alias> init <path>` into two
subcommands, parallel to `chain post`:

```
chains add <alias> init file   <path>
chains add <alias> init inline [--sign[=<key>]]
```

The `inline` form auto-generates a minimal `#`-typed genesis
from `<alias>` (used as `name`) and the signing key's public part.

## Status

Done.

- [x] version: `VERSION` tuple + `version()` in `common.lua`
- [x] inline CLI grammar (`init file` / `init inline`); chains.lua dispatch
- [x] rename `init <path>` -> `init file <path>` in tests/docs
- [x] inline `#` builds genesis; alias = name; pioneers = [pubkey]
- [x] tristate `--sign` (extension): absent / bare / `=key`, default
      `$HOME/.ssh/id_ed25519`, applied to all four `--sign` options
      (init.inline, chain.post, chain.like, chain.dislike) via shared
      `sign` action helper in `freechains.lua`
- [x] full test suite green

## CLI

| Form                                              | Behavior                                          |
|---------------------------------------------------|---------------------------------------------------|
| `chains add <alias> init file <path>`             | current behavior, just renamed                    |
| `chains add <alias> init inline [--sign[=<key>]]` | auto-generate `#`-typed genesis from `<alias>`. tristate `--sign`: absent / bare / `=<key>`. Default key = `$HOME/.ssh/id_ed25519` (substituted by the `sign` action in `freechains.lua`) |
| `chains add <alias> clone <url>`                  | unchanged                                         |

For `inline`: genesis `name = <alias>`, `type = "#"` always.
Prefix shorthand (`#`, `@`, `@!`, `$`) is deferred to a
later pass.

## Auto-generated genesis

Inline produces:

```lua
return {
    version  = {0, 20, 0},
    type     = "#",
    name     = "<alias>",
    pioneers = { "ssh-ed25519 AAAA..." },
}
```

## Pubkey extraction

Shell out:

```
ssh-keygen -y -f <sign-arg>
```

Output is a single line `ssh-ed25519 AAAA...`.
Used as `pioneers[1]`.

## Version

`VERSION` lives in `src/freechains/common.lua` as a tuple
global `{0, 20, 0}`.
Function `version()` returns the string form `"v0.20.0"`.
Inline genesis builder uses the tuple directly.
The `--version` flag prints `version()`.

## Files modified

| File                                | Change                                                  |
|-------------------------------------|---------------------------------------------------------|
| `src/freechains/common.lua`         | added `VERSION = {0, 20, 0}`, `version()` |
| `src/freechains.lua`                | new subcommands `init file`/`init inline`; tristate `--sign` action `sign(T, k, vs)` applied to inline/post/like/dislike |
| `src/freechains/chains.lua`         | `init` dispatch on `file`/`inline`; inline branch: ssh-keygen pubkey extraction, build genesis via `serial(T)`, write tmp, set `ARGS.path`, fall through to existing path-based init |
| `tst/cli-chains.lua`                | rename `init <path>` -> `init file <path>`; new section `ADD INIT INLINE` (placed after `REM` so dir is empty) |
| `tst/ssh/home/.ssh/id_ed25519`      | new symlink -> `../../key1` (HOME fixture for default-sign test) |
| 18 other `tst/*.lua`                | rename `init <path>` -> `init file <path>` |
| `.claude/plans/all.md`, `commands.md` | reflect new grammar |

## Tests

New cases in `tst/cli-chains.lua`:

| #  | Case                                                  | Expected                                |
|----|-------------------------------------------------------|-----------------------------------------|
| 1  | `chains add chat init inline --sign <key>`            | chain at `chains/chat`; genesis name=chat, type=`#`, pioneers=[pubkey] |
| 2  | `HOME=<fixture> chains add chat init inline`          | uses default `$HOME/.ssh/id_ed25519` (fixture symlink → key1) |
| 3  | `chains add x init inline --sign /nonexistent/key`    | `ERROR : chains add : invalid sign key` |
| 4  | `chains add init` / `chains add x init bogus`         | argparse error (unchanged)              |
| 5  | `init file <path>` (rename of existing tests)         | unchanged behavior                      |

## Errors (per CLAUDE.md format)

| Trigger                         | Message                                            |
|---------------------------------|----------------------------------------------------|
| `ssh-keygen -y` fails           | `ERROR : chains add : invalid sign key`            |

## Open questions

- Should the auto-generated genesis include `descr`? No — keep it
  minimal; users can switch to `file` form for richer config.

## Deferred / out of scope

- Prefix shorthand (`#`, `@`, `@!`, `$`) and `key`-typed genesis.
- A `freechains keys` wrapper. Use `ssh-keygen` directly.
- Encryption for `$` chains.
- Argparse changes beyond `init`.
