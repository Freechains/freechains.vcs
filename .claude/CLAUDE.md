# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project Overview

Freechains VCS reimplements the Freechains distributed consensus protocol
using Git as the underlying database.
It replaces the original Kotlin implementation (`../kt/`) with a
Git-native architecture using Lua.

A **chain** is a separate bare git repository (not a branch).
A **block** is a git commit.
Payloads are git blobs referenced via tree objects.
The genesis block's commit hash serves as the chain's unique identifier.

## Repository Layout

```
tst/               Lua test files + Kotlin reference tests (tst/kt/)
.claude/plans/     14 design specification documents (architecture,
                   git mapping, genesis, chains, crypto, replication, etc.)
.github/workflows/ CI configuration (tests.yml)
```

There is no `src/` directory yet — this is currently design specs + tests.

## Build & Test

### Dependencies

```bash
sudo apt-get install lua5.4 git
```

### Running Tests

TODO

### Test Structure

TODO

## Architecture

### Chain Types

| Type       | Access     | Keys field                  |
|------------|------------|-----------------------------|
| `public`   | N to N     | `pioneers={...}` (optional) |
| `private`  | N to N     | `shared="x25519:..."`       |
| `personal` | 1 to N     | `personal="ed25519:..."`    |

### Host Filesystem

```
<host>/
  config/          git repo: keys/, config.toml, peers.toml
  chains/
    <genesis-hash>/   bare git repo (the chain's DAG)
    #topic -> <hash>  symlink alias
```

### Git Mapping

| Freechains     | Git                          |
|----------------|------------------------------|
| Chain          | Bare repository              |
| Block          | Commit object                |
| Block hash     | Commit hash                  |
| Payload        | Blob in tree (file "payload")|
| Block parents  | Commit parents               |
| Genesis        | Root commit (zeroed fields)  |
| Signature      | Extra commit headers         |

Signatures are embedded as extra headers (`freechains-pubkey`,
`freechains-sig`) inside the commit object (part of the hash), not
as GPG signatures (which are outside the hash).

### Replication

- **Owner peers**: sync both `config/` and `chains/` via git
  push/pull as-is
- **Non-owner peers**: sync only `chains/` with Freechains acceptance
  rules (reputation, signature validation)

## Design Documents

Key specs in `.claude/plans/`:

| File             | Topic                                         |
|------------------|-----------------------------------------------|
| `all.md`         | Architecture overview and design rationale     |
| `git.md`         | Git as database: commit fields, DAG traversal  |
| `genesis.md`     | Deterministic genesis block specification      |
| `chains.md`      | Chain types, identification, synchronization   |
| `layout.md`      | Filesystem layout: config/ + chains/           |
| `replication.md` | Owner vs non-owner sync rules                  |
| `signing.md`     | Signature embedding in commit headers          |
| `crypto.md`      | Crypto choices (openssl, luasodium)            |
| `commands.md`    | Freechains CLI to Git command mapping          |
| `tests.md`       | Test catalog (58 tests across sections A–X)    |
| `merge-hook.md`  | Pre-merge-commit consensus verification        |
