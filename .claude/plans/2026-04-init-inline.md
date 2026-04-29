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
- [x] inline CLI grammar (`init file` / `init inline`); chains.lua dispatch stub
- [x] rename `init <path>` -> `init file <path>` in tests/docs
- [x] failing tests for inline form (red until inline impl lands)
- [x] inline `#` builds genesis; `@`, `@!`, `$` -> `assert(false, "TODO")`

## CLI

| Form                                              | Behavior                                          |
|---------------------------------------------------|---------------------------------------------------|
| `chains add <alias> init file <path>`             | current behavior, just renamed                    |
| `chains add <alias> init inline [--sign[=<key>]]` | auto-generate `#`-typed genesis from `<alias>`. tristate `--sign`: absent → use default; bare → default; `=<key>` → that key. Default = `SIGN` (global in `common.lua` = `$HOME/.ssh/id_ed25519`) |
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
