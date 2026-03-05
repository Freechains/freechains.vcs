# Plan: Non-Deterministic Genesis + `chains add/rem/list` CLI

## Context

The KT (Kotlin) version uses deterministic genesis: `join` with the
same parameters always produces the same chain hash.
The VCS (Git-native) version departs from this: each `chains add`
creates a **unique** genesis commit using real values (creator pubkey,
current timestamp).
This makes `create` and `clone` distinct operations, both handled
through the `chains add` command.

**Scope**: Update design specs + implement Lua CLI.

## Design Decisions (from interview)

| Decision               | Choice                                  |
|------------------------|-----------------------------------------|
| Git fields             | Real values (pubkey, timestamp)         |
| Join flow              | `git clone` from peer                   |
| CLI commands           | `chains add/rem/list` (not join/leave)  |
| Message format         | Keep Lua literal serialization          |
| User field             | Keep separate, opaque to protocol       |
| Creator identity       | Ed25519 pubkey in author/committer      |
| Add API                | `<alias> --type <char> [--flags]`       |
| Add + clone            | `<alias> --clone <hash> --peer <url>`   |
| Add + lua file         | `<alias> --file genesis.lua`            |
| Rem behavior           | Delete repo + symlink                   |
| Type chars             | `#`=public `$`=private `@`=personal     |
|                        | `@!`=personal+writeable                 |
| Alias prefix           | If alias starts with #/$/@, infer type  |

## Steps

- [ ] Step 1 — Update genesis.md
- [ ] Step 2 — Update chains.md
- [ ] Step 3 — Update commands.md
- [ ] Step 4 — Rewrite freechains-chains-cli.md
- [ ] Step 5 — Implement src/freechains
- [ ] Step 6 — Create Makefile
- [ ] Step 7 — Update tests spec
