# Metadata: Data Inventory and Storage

## Overview

All chain-level metadata lives under `.freechains/` inside
each chain repo. Split into two subdirectories by
replication scope:

```
<chain-repo>/
  .freechains/
    shared/          <- replicated via git (all peers see this)
    local/           <- never leaves this peer
```

**Shared** = tracked by git, propagated during sync.
All peers holding the chain have the same shared data
(deterministic, rebuildable from DAG).

**Local** = gitignored, specific to this peer's identity
and computed state. Never synced. Deletable and
rebuildable.

---

## Chain-Level Metadata

### Shared + Immutable

Set once at chain creation. Never modified after genesis.

| File | Content | Set by |
|------|---------|--------|
| `shared/genesis.lua` | Chain definition: `{version, type, [key], [shared], [tolerance]}` | `chains add` |
| `shared/reps/authors.lua` (genesis) | Pioneer initial reputation: `{[pubkey]=30000/N, ...}` | `chains add` |

`genesis.lua` defines the chain's identity and rules.
`reps/authors.lua` in the genesis commit defines pioneers
by their non-zero entries. Both are committed in the
genesis commit and never modified — the genesis commit
hash **is** the chain identifier.

### Shared + Mutable

Updated during normal chain operation. All peers converge
to the same state (deterministic from DAG walk).

| File | Content | Updated by |
|------|---------|------------|
| `shared/reps/authors.lua` | Author → internal reputation: `{[pubkey]=N, ...}` | Every post/like commit |
| `shared/reps/posts.lua` | Post → internal reputation: `{[hash]=N, ...}` | Every like/dislike commit |
| `shared/likes/` | Like payload files | Like/dislike commits |
| `shared/dropped-sets/<hash>.list` | Vetoed commit hashes (one per line) | Veto passes (>50%) |
| `shared/peers.lua` | Known peers with real IPs in the network: `{[pubkey]=url, ...}` | Peer announcements |

`peers.lua` is the chain-level peer directory — a shared
registry of peers participating in this chain, with their
real network addresses. Any peer can announce itself by
posting a signed commit. This is **shared** because all
peers need to discover each other. Contrast with
`local/neighbours.lua`, which is which of these peers
*this node* actually syncs with.

Note: `reps/authors.lua` has two lives — immutable in the
genesis commit (pioneer definitions), mutable in HEAD
(current reputation state). The genesis version is
reconstructible; the HEAD version is a cache updated on
every commit.

### Local + Immutable

Set once per peer for this chain. Never changes unless
the peer reconfigures.

| File | Content | Set by |
|------|---------|--------|
| `local/owner` | Owner's pubkey for this repo (one line) | `chains add` / `chains join` |

The owner key determines the peer's identity in votes
and fork decisions. It's the pubkey from `config/keys/`
that was active when the chain was joined.

### Local + Mutable

Computed state, caches, and per-peer decisions. Deletable
and rebuildable (except `fork`, which records a decision).

| File | Content | Updated by |
|------|---------|------------|
| `local/fork` | Fork choice: line 1 = fork-point hash, line 2 = our-side hash | Hard fork trigger |
| `local/neighbours.lua` | Peers this node pushes/pulls to: `{[url]=pubkey, ...}` | User config / `peer add` |
| `local/cache.sqlite` | Consensus linearization + reputation checkpoints | Post-merge hook |

`fork` records which side of a hard fork this peer chose
(based on owner's vote). Once written, merges from the
other fork are rejected by the pre-merge guard.

`neighbours.lua` lists the peers this node actively syncs
with (push/pull targets). This is **local** because each
peer has its own sync partners — A may sync with B and C,
while B syncs with A and D. The neighbour list is a
per-node operational decision, not shared state.

`cache.sqlite` holds two tables:

```sql
-- Linearized consensus order (recomputed after each sync)
CREATE TABLE consensus (
    position INTEGER PRIMARY KEY,
    hash     TEXT
);

-- Reputation snapshot at a known commit (avoids full replay)
CREATE TABLE rep_checkpoint (
    at_hash     TEXT,
    author_pub  TEXT,
    reps        INTEGER,
    PRIMARY KEY (author_pub)
);
```

---

## Host-Level Metadata

Lives in `config/` (a separate git repo at the host
level, not inside any chain).

### Local to owner (synced between owner peers only)

| File | Content | Mutable? |
|------|---------|----------|
| `config/keys/<pubkey>.pub` | Ed25519 public key (GPG export) | Immutable |
| `config/keys/<pubkey>.key` | Encrypted private key (GPG export) | Immutable |
| `config/config.toml` | Host port, default peers, active key | Mutable |
| `config/peers.toml` | Known peers registry | Mutable |

Config is **never** shared with non-owner peers.
Between owner peers (same person, different machines),
it replicates via `git push/fetch+merge` with full trust.

---

## Commit-Level Metadata (in DAG)

Not files — embedded in git commit objects. Shared by
definition (part of the DAG that all peers replicate).

### Commit headers / trailers

| Field | Location | Mutable? | Content |
|-------|----------|----------|---------|
| `author` | Commit header | Immutable | `<pubkey> <timestamp>` |
| `committer` | Commit header | Immutable | `<pubkey> <timestamp>` |
| `gpgsig` | Commit header | Immutable | GPG signature |
| `freechains-like` | Commit header | Immutable | `+N <target-hash-or-pubkey>` |
| `freechains-vote` | Commit header | Immutable | `<fork-point> <branch-side>` |
| `Freechains-Kind` | Trailer | Immutable | `post` / `like` |
| `Freechains-Ref` | Trailer | Immutable | Target commit hash |
| `Freechains-Peer` | Trailer | Immutable | Peer pubkey (on merge commits) |

All commit-level metadata is immutable by definition —
commits are content-addressed.

---

## Summary Table

| Data | Scope | Mutability | Path |
|------|-------|------------|------|
| genesis.lua | shared | immutable | `.freechains/shared/genesis.lua` |
| pioneer reps | shared | immutable | `.freechains/shared/reps/authors.lua` (genesis) |
| author reps | shared | mutable | `.freechains/shared/reps/authors.lua` (HEAD) |
| post reps | shared | mutable | `.freechains/shared/reps/posts.lua` |
| like payloads | shared | mutable | `.freechains/shared/likes/` |
| dropped sets | shared | mutable | `.freechains/shared/dropped-sets/` |
| peer directory | shared | mutable | `.freechains/shared/peers.lua` |
| owner identity | local | immutable | `.freechains/local/owner` |
| fork choice | local | mutable | `.freechains/local/fork` |
| neighbours | local | mutable | `.freechains/local/neighbours.lua` |
| cache DB | local | mutable | `.freechains/local/cache.sqlite` |
| keys | host | immutable | `config/keys/` |
| host config | host | mutable | `config/config.toml` |
| peer registry | host | mutable | `config/peers.toml` |
| commit headers | DAG | immutable | (in git commit objects) |
| trailers | DAG | immutable | (in git commit messages) |

---

## .gitignore for local/

```gitignore
# .freechains/.gitignore
local/
```

Everything under `local/` is gitignored — it never
enters the DAG, never replicates, and can be deleted
and rebuilt (except `fork`, which is a decision record).

---

## Rebuild Rules

| Data | Rebuildable? | How |
|------|-------------|-----|
| `shared/genesis.lua` | Yes | Always in genesis commit's tree |
| `shared/reps/authors.lua` | Yes | Replay DAG walk from genesis |
| `shared/reps/posts.lua` | Yes | Replay DAG walk from genesis |
| `shared/dropped-sets/` | Yes | Replay vote commits, recompute threshold |
| `shared/peers.lua` | Yes | Replay peer announcement commits |
| `local/owner` | No | Must be set by user (which key to use) |
| `local/fork` | Partially | Can recompute from votes + owner, but owner's vote is the input |
| `local/neighbours.lua` | No | User's sync partner choices (operational) |
| `local/cache.sqlite` | Yes | Recompute from git history |

---

## Related Plans

- [layout.md](layout.md) — Host directory structure
- [genesis.md](genesis.md) — Genesis block specification
- [reps.md](reps.md) — Reputation system and storage
- [merge.md](merge.md) — Veto (dropped sets) and fork
- [sqlite.md](sqlite.md) — Cache database schema
- [signing.md](signing.md) — Key storage and GPG signing
- [replication.md](replication.md) — Sync rules (owner vs non-owner)
