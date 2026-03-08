# Filesystem Layout

## Host Directory

A Freechains host is a directory with two top-level subdirectories, each backed by git:

```
<host>/
  config/                           <- git repo (plain files)
    keys/
      <pubkey>.pub                  <- public key
      <pubkey>.key                  <- encrypted private key
    config.toml                     <- host port, default peers, key to use
    peers.toml                      <- known peers registry
  chains/                           <- one git repo per chain
    <chain-hash>/                   <- git working tree (DAG + blocks)
      .freechains/
        genesis.lua                <- genesis block definition
        reps-authors.lua           <- author → reputation (Lua table)
        reps-posts.lua             <- post → like/dislike counts (Lua table)
    @francisco -> <chain-hash>/     <- symlink alias (human-readable name)
    #sports    -> <chain-hash>/     <- symlink alias
    $friends   -> <chain-hash>/     <- symlink alias
```

### config/

A standard git working tree containing configuration and key material. Not a freechains chain — no blocks, no consensus, no reputation. Just files tracked by git.

### chains/

Contains one git repo per chain (currently working trees, not
bare repos). Each chain is an independent repository. Symlinks
provide human-readable aliases.

## Replication Model

Both `config/` and `chains/` use git for replication, but the rules differ based on peer ownership.

### Same-owner peers (owner ↔ owner)

| Directory | Sync method | Rules |
|---|---|---|
| `config/` | `git push` / `git fetch+merge` | As-is. Full trust. All files replicate without filtering. |
| `chains/` | `git push` / `git fetch+merge` (per chain repo) | As-is. Full trust. All blocks replicate without filtering. |

The owner's own peers are extensions of the same node. Config and chains replicate identically — it's the same person on different machines.

### Different-owner peers (owner ↔ other)

| Directory | Sync method | Rules |
|---|---|---|
| `config/` | **Never synced** | Config is private to the owner. Other peers never see it. |
| `chains/` | `git fetch` + freechains merge | Freechains rules apply: reputation, consensus, block acceptance pipeline. Only chains both peers have joined are synced. |

### Summary

```
owner-peer A  <-- config: git push/pull -->  owner-peer B
              <-- chains: git push/pull -->

owner-peer A  <-- config: NEVER        -->  other-peer C
              <-- chains: freechains    -->  other-peer C
```

## Chain naming and aliases

Symlinks give human-readable names while actual storage is content-addressed, mirroring Freechains' own naming convention (`@pubkey`, `#topic`, `$private`):

| Symlink name | Meaning |
|---|---|
| `@<pubkey>` | Single-author identity chain |
| `#<topic>` | Public topic chain |
| `$<name>` | Private shared chain |

The `.freechains/` directory inside each chain repo holds
genesis and reputation state as Lua tables — all tracked
by git. If deleted, they can be fully reconstructed by
replaying the git history.

## XDG Mapping (per-user default)

```
~/.local/share/freechains/        <- XDG_DATA_HOME
  config/                          <- git repo
  chains/                          <- git repos (one per chain)
```
