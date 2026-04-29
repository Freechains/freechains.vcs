# Plan: `chains add ... init inline`

## Goal

Split `freechains chains add <alias> init <path>` into two
subcommands, parallel to `chain post`:

```
chains add <alias> init file   <path>
chains add <alias> init inline <name> --sign <key>
```

The `inline` form auto-generates a minimal genesis from a
type-prefixed `<name>` and the signing key.

## Status

In progress.

- [x] version: `VERSION` tuple + `version()` in `common.lua`
- [ ] inline CLI grammar (`init file` / `init inline`)
- [ ] inline `#` builds genesis; `@`, `@!`, `$` -> `assert(false, "TODO")`
- [ ] rename `init <path>` -> `init file <path>` in tests/docs
- [ ] new tests for inline form

## CLI

| Form                                               | Behavior                                          |
|----------------------------------------------------|---------------------------------------------------|
| `chains add <alias> init file <path>`              | current behavior, just renamed                    |
| `chains add <alias> init inline <name> --sign <k>` | auto-generate genesis from `<name>` and pubkey    |

`<name>` shorthand:

| Prefix | Type   | Auto-generated extras                      |
|--------|--------|--------------------------------------------|
| `#`    | `'#'`  | `pioneers = { <pubkey> }`                  |
| `@`    | `'@'`  | `key = <pubkey>`                           |
| `@!`   | `'@!'` | `key = <pubkey>`                           |
| `$`    | `'$'`  | error : encryption not yet wired           |

## Auto-generated genesis

Inline form for `#chat`:

```lua
return {
    version  = {0, 20, 0},
    type     = "#",
    name     = "chat",
    pioneers = {
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...",
    },
}
```

Inline form for `@me`:

```lua
return {
    version = {0, 20, 0},
    type    = "@",
    name    = "me",
    key     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...",
}
```

## Pubkey extraction

Shell out:

```
ssh-keygen -y -f <sign-arg>
```

Output is a single line `ssh-ed25519 AAAA...`.
Trim trailing whitespace.
Use the same string as `pioneers[1]` (for `#`) or
`key` (for `@`/`@!`).

For literal `key::ssh-ed25519 AAAA...` form, parse directly
without shellout.

## Version

`VERSION` lives in `src/freechains/common.lua` as a tuple
global `{0, 20, 0}`.
Function `version()` returns the string form `"v0.20.0"`.
Inline genesis builder uses the tuple directly.
The `--version` flag prints `version()`.

## Files to modify

| File                                | Place                          | Change                                                                                                          |
|-------------------------------------|--------------------------------|-----------------------------------------------------------------------------------------------------------------|
| `src/freechains.lua`                | `cmd.chains.add.init`          | replace `:argument("path")` with two subcommands `file` (positional `path`) and `inline` (positional `name`, option `--sign`) |
| `src/freechains/chains.lua`         | `add` function                 | branch on `ARGS.file` vs `ARGS.inline`; for inline: parse `<name>`, build genesis Lua source, write to a temp file, then existing path-based code |
| `tst/cli-chains.lua`                | every `init <path>` invocation | rename to `init file <path>`; add new tests for `init inline '#name' --sign ...` |
| `tst/cli-post.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-like.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-sign.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-reps.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-now.lua`                   | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-time.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-begs.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-recv.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-send.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/cli-order.lua`                 | `init <path>`                  | rename to `init file <path>` |
| `tst/sync.lua`                      | `init <path>`                  | rename to `init file <path>` |
| `tst/consensus.lua`                 | `init <path>`                  | rename to `init file <path>` |
| `tst/err-post.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/err-like.lua`                  | `init <path>`                  | rename to `init file <path>` |
| `tst/repl-local-head.lua`           | `init <path>`                  | rename to `init file <path>` |
| `tst/repl-remote-head.lua`          | `init <path>`                  | rename to `init file <path>` |
| `tst/repl-local-begs.lua`           | `init <path>`                  | rename to `init file <path>` |
| `tst/repl-remote-begs.lua`          | `init <path>`                  | rename to `init file <path>` |
| `README.md`                         | walkthrough Step 5             | use `init inline '#chat' --sign ~/.ssh/id_ed25519` |
| `.claude/plans/genesis.md`          | CLI section                    | document the two subcommands |
| `.claude/plans/commands.md`         | `chains add` row               | document the two subcommands |
| `.claude/plans/freechains-cli.md`   | scope section                  | reflect the new grammar |

(Sweep `tst/` for stragglers — the list above is from `grep`-ed
guesses; verify before editing.)

## Tests

New cases in `tst/cli-chains.lua`:

| #  | Case                                                | Expected                                          |
|----|-----------------------------------------------------|---------------------------------------------------|
| 1  | `init inline '#chat' --sign <key>`                  | chain created, pioneers = [pubkey]                |
| 2  | `init inline '@me' --sign <key>`                    | chain created, key = pubkey                       |
| 3  | `init inline '@!me' --sign <key>`                   | chain created, type='@!', key = pubkey            |
| 4  | `init inline '$secret' --sign <key>`                | error : `'$' shorthand requires shared key`       |
| 5  | `init inline '#chat'` (no `--sign`)                 | error : `inline requires --sign`                  |
| 6  | `init inline 'chat' --sign <key>` (no prefix)       | error : `invalid name shorthand`                  |
| 7  | `init inline '#' --sign <key>` (empty name)         | error : `invalid name shorthand`                  |
| 8  | `init file <path>` (rename of existing tests)       | unchanged behavior                                |

## Errors (per CLAUDE.md format)

| Trigger                         | Message                                                |
|---------------------------------|--------------------------------------------------------|
| inline without `--sign`         | `ERROR : chains add : inline requires --sign`          |
| invalid name shorthand          | `ERROR : chains add : invalid name shorthand`          |
| `$` prefix                      | `ERROR : chains add : '$' shorthand not yet supported` |
| `ssh-keygen -y` fails           | `ERROR : chains add : invalid sign key`                |

## Open questions

- Should `init inline '#chat'` infer the alias from the name when
  the alias is omitted? (Argparse currently forces alias as a
  positional.) Defer.
- Should the auto-generated genesis include `descr`? No — keep it
  minimal; users can switch to `file` form for richer config.
- Future `$` support: depends on encryption being wired
  (currently doc-only).

## Out of scope

- A `freechains keys` wrapper. Use `ssh-keygen` directly.
- Encryption for `$` chains (separate plan).
- Argparse changes beyond `init`.
