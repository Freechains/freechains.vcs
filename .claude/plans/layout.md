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
        random                     <- uniqueness seed
        likes/                     <- like commits
        local/                     <- UNTRACKED (per-node state)
          now.lua                  <- last time effects timestamp
          authors.lua              <- author → {reps, time}
          posts.lua                <- post → {author, time, state, reps}
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

See [replication.md](replication.md) for the full
owner/non-owner sync rules and trust levels.

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
