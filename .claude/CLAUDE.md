# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project Overview

Freechains VCS reimplements the Freechains distributed consensus protocol
using Git as the underlying database.
It replaces the original Kotlin implementation (`../kt/`) with a
Git-native architecture using shell scripts and Lua.

A **chain** is a separate bare git repository (not a branch).
A **block** is a git commit.
Payloads are git blobs referenced via tree objects.
The genesis block's commit hash serves as the chain's unique identifier.

## Repository Layout

```
tst/kt/           Kotlin reference tests (all.kt) + shell integration
                   tests (general.sh, peer.sh, pubpvt.sh, like.sh, sync.sh)
.claude/plans/     14 design specification documents (architecture,
                   git mapping, genesis, chains, crypto, replication, etc.)
.github/workflows/ CI configuration (tests.yml)
```

There is no `src/` directory yet — this is currently design specs + tests.

## Build & Test

### Dependencies

```bash
sudo apt-get install openssl lua5.4 git \
  libsodium-dev luarocks liblua5.4-dev
sudo luarocks --lua-version 5.4 install luasodium
```

### Running Tests

CI runs from `tst/` directory:

```bash
cd tst && make clean && make a && make a-lua
```

The Kotlin integration tests (`tst/kt/`) use `freechains-host` and
`freechains` CLI binaries (from the Kotlin build) and run as shell
scripts:

```bash
cd tst/kt
./clean.sh              # kill java processes, wipe /tmp/freechains/
./general.sh            # host/chain/post/sync integration
./peer.sh               # peer synchronization
./pubpvt.sh             # public/private chain tests
./like.sh               # like/dislike mechanism
./tests.sh              # infinite loop running all of the above
```

Test data lives under `/tmp/freechains/`.

### Test Structure

- **Section A** (`a1`–`a4`): Primitives — data round-trip, symmetric
  encryption, asymmetric encryption + signing, sorted set difference
- **Section B** (`b1`–`b3`): Host init, chain/block persistence,
  directory replication
- **Section X** (`x1`): Genesis block determinism
- **Kotlin `all.kt`**: 136 test functions covering consensus ordering,
  reputation, likes, merges, peer sync (reference from the original
  Kotlin implementation)

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
