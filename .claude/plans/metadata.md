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
were introduced during plan development. All need review
before implementation.

**`shared/dropped-sets/`** — introduced in merge-hook.md.
The original design (merge.md) says a veto drops the
merge commit and all commits reachable only through its
second parent. The veto decision is recorded as a special
commit (`Freechains-Kind: veto`, `Freechains-Ref:
<rejected-merge-hash>`) on the surviving branch. But
during fetch validation, the pre-merge hook needs to
quickly answer: "is this incoming commit one that was
already vetoed?" Walking the DAG to find veto commits
and then computing their reachability sets on every fetch
is expensive. `dropped-sets/` materializes the answer —
one file per veto, listing the hashes that were dropped.
It's a shared cache: deterministic from the DAG (any
peer can rebuild it from veto commits), but storing it
avoids recomputation. Question: is this redundant with
the veto commit itself? Could the hook just walk veto
commits instead?

**`local/owner`** — introduced in metadata.md. The
original design (replication.md) defines "owner peers" as
peers sharing the same key material — they replicate with
full trust, no validation. But nothing says how a peer
knows *which* pubkey from `config/keys/` is bound to
*this* chain repo. When a chain is joined, the peer must
record which key it's using, because: (1) the pre-merge
hook needs to know the owner's pubkey to check fork
votes, (2) replication needs to distinguish owner vs
non-owner peers, (3) a host may have multiple keys (e.g.,
one personal key, one organizational key). This file
stores one line: the pubkey that was active when the
chain was created or joined. Question: could this be
derived from git config instead of a separate file?

**`local/fork`** — introduced in merge-hook.md. The
original design (merge.md) says when a fork divergence
crosses a threshold, the chain hard-forks. Each peer
follows its owner's vote: if owner voted for branch X,
the repo follows chain-X; merges from branch Y are
rejected. But the pre-merge hook runs on every
`git merge` — it needs to know, right now, which side
this peer chose. Without a persistent record, the hook
would have to: find the fork point, collect all vote
commits, weight them by prefix reputation, determine the
owner's vote, and compute the winning side — on every
single merge. `local/fork` caches that decision: line 1
is the fork-point hash, line 2 is the chosen branch tip.
Once written, the hook just checks "is the incoming
merge from the other side?" and rejects if so. Question:
what happens if the owner changes their vote? Is the
fork decision final or reversible?

**`local/cache.sqlite`** — introduced in sqlite.md. The
original design (reps.md) defines reputation as a
deterministic function of the DAG: walk commits in
`--date-order` from genesis, apply costs (posting costs
1 rep, likes transfer rep with 10% tax, merge-only
commits are skipped). This means computing any author's
current reputation requires replaying the entire chain
history. For a chain with thousands of commits, this is
too slow for every post or like operation. The cache
stores two things: (1) the consensus linearization order
(which commits, in what sequence), and (2) a reputation
checkpoint (author reps at a known commit hash). To get
current reps, replay only from the checkpoint forward.
Pure optimization — deletable and rebuildable from git
history. Question: is sqlite the right choice, or would
a simple lua file (like reps/authors.lua) suffice?

**`config/config.toml`** — introduced in layout.md. The
original design has CLI commands like `freechains host
create` and `freechains host start --port 8330`, but
doesn't specify where host-level settings persist on
disk. The `config/` directory is a separate git repo (not
inside any chain), holding keys and settings. Config
stores: which port to listen on, which key is currently
active, and default peer addresses for new chains. It's
never shared with non-owner peers — only replicated
between owner peers (same person, different machines) via
`git push/fetch`. Question: TOML vs lua for consistency
with chain-level files?

**`config/peers.toml`** — introduced in layout.md. The
original design has peer synchronization but three
different levels of "peer list" aren't distinguished:
(1) `config/peers.toml` — host-level registry of all
known peers across all chains, (2) `shared/peers.lua` —
chain-level directory of peers participating in a
specific chain, with real network addresses, shared with
all chain members, (3) `local/neighbours.lua` —
per-chain, per-node list of which peers this node
actually syncs with (push/pull targets). The host-level
registry is the broadest: "all peers I've ever heard of."
Chain-level `peers.lua` is narrower: "peers in this
chain." Neighbours is narrowest: "peers I actively sync
with for this chain." Question: is the host-level
registry actually needed, or can it be derived from the
union of all chain-level peer directories?

**`freechains-vote` header** — introduced in commands.md.
The original design (merge.md) says fork resolution is
owner-driven: authors vote for a branch, votes are
weighted by prefix reputation (reputation computed up to
the fork point, not beyond), and when the difference
crosses a threshold the chain hard-forks. But the vote
itself needs a commit format. The header
`freechains-vote: <fork-point-hash> <branch-side-hash>`
is a signed commit (like a like/dislike) that declares
the author's branch preference. The fork-point hash
identifies which fork this vote is about (a chain could
have multiple forks). The branch-side hash identifies
which branch the author supports. Question: should this
be a trailer (`Freechains-Vote`) instead of an extra
header, for consistency with other Freechains metadata?

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
