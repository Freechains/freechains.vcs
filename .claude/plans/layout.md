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
    <chain-id>/                   <- BARE git repo (DAG + blocks)
      .freechains/
        genesis.lua                <- tracked: genesis block definition
        random                     <- tracked: uniqueness seed
        likes/                     <- tracked: like commits
        authors.lua                <- tracked: author → {reps, time}
        posts.lua                  <- tracked: post → {author, time, state, reps}
        now.lua                    <- UNTRACKED: last time effects timestamp
    sports     -> <chain-id>/     <- symlink alias (`/sports`)
    friends    -> <chain-id>/     <- symlink alias (`/friends`)
```

### config/

A standard git working tree containing configuration and key material. Not a freechains chain — no blocks, no consensus, no reputation. Just files tracked by git.

### chains/

Contains one BARE git repo per chain (no working tree: reads go
through `cat-file`/`ls-tree` on HEAD's tree, writes through
`hash-object`/`update-index`/`commit-tree`). Each chain is an
independent repository. Symlinks provide human-readable aliases.

## Replication Model

See [replication.md](replication.md) for the full
owner/non-owner sync rules and trust levels.

## Chain naming and aliases

Symlinks give human-readable names while actual storage is
content-addressed.
Aliases are written `/<name>` on the command line (shell-safe,
no quotes) and stored as `chains/<name>`; nested `/a/b` is reserved.
Chain types (public, private, identity) belong to the genesis, not
to the alias.
See [260828-slash.md](260828-slash.md).

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
