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

Set once at chain creation. Has a validation rule: must
never change after genesis.

| File | Content | Set by |
|------|---------|--------|
| `shared/genesis.lua` | Chain definition: `{version, type, [key], [shared], [tolerance]}` | `chains add` |

`genesis.lua` defines the chain's identity and rules.
The genesis commit hash **is** the chain identifier.
This is the only file with a real immutability
constraint — validation rejects any commit that modifies
it. (Other files in the genesis commit are immutable only
in the trivial sense that all committed data is
content-addressed.)

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

`reps/authors.lua` — initial state in the genesis commit
defines pioneers (non-zero entries = pioneers). Updated
on every subsequent commit. The genesis version is just
the first snapshot, like any other commit.

`peers.lua` — chain-level peer directory. Shared registry
of peers participating in this chain, with real network
addresses. Any peer can announce itself by posting a
signed commit. Contrast with `local/neighbours.lua`,
which is which of these peers *this node* actually syncs
with.

`dropped-sets/` — **INVENTED** (not in original design).
Created as part of the veto guard in merge-hook.md.
Stores hashes of commits dropped by a veto decision.
Needs review.

### Origin tracking

Items **not from the original Freechains design** that
were introduced during plan development:

| Item | Introduced in | Purpose |
|------|--------------|---------|
| `shared/dropped-sets/` | merge-hook.md (veto guard) | Track vetoed commit hashes |
| `local/owner` | metadata.md | Store which pubkey owns this repo |
| `local/fork` | merge-hook.md (fork guard) | Track hard fork choice |
| `local/cache.sqlite` | sqlite.md | Consensus + reputation cache |
| `config/config.toml` | layout.md | Host port, default peers, active key |
| `config/peers.toml` | layout.md | Known peers registry |
| `freechains-vote` header | commands.md | Vote for a branch in a fork |

All need review before implementation.

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
| `local/neighbours.lua` | Peers this node syncs with, split by direction (see below) | User config / `peer add` |
| `local/cache.sqlite` | Consensus linearization + reputation checkpoints | Post-merge hook |

`fork` records which side of a hard fork this peer chose
(based on owner's vote). Once written, merges from the
other fork are rejected by the pre-merge guard.

`neighbours.lua` lists the peers this node actively syncs
with, split by direction:

```lua
return {
    pull = {              -- peers I fetch from
        ["http://B:8330"] = "pubkey-B",
        ["http://C:8330"] = "pubkey-C",
    },
    push = {              -- peers I push to
        ["http://B:8330"] = "pubkey-B",
    },
}
```

Pull and push are independent choices. A node may pull
from many peers (receive content) but push to few (or
none — passive consumer). Conversely, a seed node may
push to many but pull from few. This asymmetry is
intentional: pull = "I want their content", push = "I
want them to have my content."

This is **local** because each peer has its own sync
partners — A may pull from B and C, push only to B,
while B pulls from A and D, pushes to all three.

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
| author reps | shared | mutable | `.freechains/shared/reps/authors.lua` |
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
