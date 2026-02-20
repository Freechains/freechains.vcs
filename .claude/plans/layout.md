# Filesystem Layout

Bare repos (no working tree) are the right choice for storage — same as how `git daemon` and GitLab serve repos. A bare repo has no checked-out files, just the git internals, which is all a Freechains node needs.

## Per-user (XDG compliant)

```
~/.local/share/freechains/        <- XDG_DATA_HOME
  chains/
    <chain-hash>/                 <- bare git repo (DAG + blocks)
    <chain-hash>.db               <- SQLite cache (consensus + rep checkpoint)
    @francisco -> <chain-hash>/   <- symlink alias (human-readable name)
    #sports    -> <chain-hash>/   <- symlink alias
    $friends   -> <chain-hash>/   <- symlink alias
  keys/
    <pubkey>.pub                  <- public key
    <pubkey>.key                  <- encrypted private key

~/.config/freechains/             <- XDG_CONFIG_HOME
  config.toml                     <- host port, default peers, key to use
```

## Global / system node (seed node)

```
/var/lib/freechains/              <- FHS: persistent application data
  chains/
    <chain-hash>/                 <- bare git repo
    <chain-hash>.db               <- SQLite cache
  peers.conf                      <- known peers registry
```

## Chain naming and aliases

Symlinks give human-readable names while actual storage is content-addressed, mirroring Freechains' own naming convention (`@pubkey`, `#topic`, `$private`):

| Symlink name | Meaning |
|---|---|
| `@<pubkey>` | Single-author identity chain |
| `#<topic>` | Public topic chain |
| `$<name>` | Private shared chain |

The `.db` SQLite file sits adjacent to its bare repo — easy to identify, easy to delete and rebuild for a specific chain without touching others. If the `.db` is deleted, it can be fully reconstructed by replaying the git history in the adjacent repo.
