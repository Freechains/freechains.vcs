# Replication: config/ and chains/

## Two directories, two trust levels

A Freechains host has two git-backed directories. Replication rules depend on whether the remote peer shares the same owner.

### config/

The `config/` directory is a standard git working tree. It holds configuration files and cryptographic keys — **not** freechains chains. No blocks, no consensus, no reputation. Just plain files under version control.

**Replication rules:**
- **Owner peers**: `git push` / `git pull` — replicate everything as-is.
- **Non-owner peers**: never synced. Config is private.

This makes config behave like a dotfiles repo that syncs across your own machines.

### chains/

The `chains/` directory holds one bare git repo per chain. Each chain is an independent repository with its own DAG of blocks.

**Replication rules:**
- **Owner peers**: `git push` / `git pull` per chain repo — replicate as-is, full trust.
- **Non-owner peers**: `git fetch` + freechains acceptance pipeline — reputation checks, consensus ordering, block validation. Only chains both peers have joined are synced.

## Owner identity

Two peers share the same owner if they can prove possession of the same private key. In practice:
- The owner's public key is in `config/keys/`
- Owner peers have the same key material (replicated via config sync)
- When connecting to a remote, the owner authenticates with their key

## Git operations

### config/ sync (owner ↔ owner)

```bash
# peer A pushes config to peer B
cd <host>/config
git push <peer-B-url>/config main

# peer B pulls config from peer A
cd <host>/config
git pull <peer-A-url>/config main
```

Config is a single branch (`main`). Conflicts are resolved by the owner — this is personal configuration, not consensus.

### chains/ sync (owner ↔ owner)

```bash
# for each chain repo, push/pull directly
for chain in <host>/chains/*/; do
    GIT_DIR="$chain" git push <peer-B-url>/chains/$(basename $chain) main
done
```

Same as config: full trust, no filtering. All blocks transfer.

### chains/ sync (owner ↔ other)

```bash
# fetch from remote peer
GIT_DIR="<chain-repo>" git fetch <other-peer-url>/<chain> main

# apply freechains acceptance pipeline to new commits
# - verify signatures (freechains-pubkey / freechains-sig)
# - check reputation (author has enough reps to post)
# - enforce size limits (128KB payload)
# - compute consensus ordering

# if all blocks pass: merge
GIT_DIR="<chain-repo>" git merge FETCH_HEAD --no-edit
# mark as sync-only merge (freechains-sync: true header)
```

Blocks that fail validation are rejected — the fetch is discarded (or the offending commits are filtered out before merge).

## Why git for both?

| Alternative | Problem |
|---|---|
| rsync | No history, no conflict detection, no incremental sync |
| Custom protocol | Reinventing git's packfile transfer |
| Shared filesystem | Not distributed |

Git already solves: content addressing, incremental transfer (packfiles), conflict detection (merge), history (log), and transport (ssh, https, git://). Using it for both config and chains means one replication mechanism to understand, debug, and secure.

## Diagram

```
          OWNER PEER A                    OWNER PEER B
       ┌──────────────┐               ┌──────────────┐
       │  config/     │── git push ──>│  config/     │
       │  (git repo)  │<── git pull ──│  (git repo)  │
       │              │               │              │
       │  chains/     │── git push ──>│  chains/     │
       │  (bare repos)│<── git pull ──│  (bare repos)│
       └──────┬───────┘               └──────────────┘
              │
              │ chains only, freechains rules
              │
       ┌──────▼───────┐
       │  OTHER PEER C │
       │  chains/      │
       │  (bare repos) │
       └──────────────┘
```
