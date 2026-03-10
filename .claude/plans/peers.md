# Peers

---

## 1. What is a Peer

A peer is a host running a freechains node. Each peer has:
- A local filesystem with `config/` and `chains/` dirs
- One or more chain repositories (git working trees)
- An identity: Ed25519 public key (chain-level)
- A git daemon or other transport for sync

Peers are **not** the same as authors. An author posts
content; a peer relays and validates it. One machine can
host multiple author identities but is always one peer.

---

## 2. Peer Identity in the DAG

### `Freechains-Peer: <pubkey>` trailer

Every merge commit carries a trailer identifying the peer
that performed the sync (see trailer.md):

```
--trailer 'Freechains-Peer: CA6391CE...'
```

Combined with GPG signing (`git commit -S`), this is a
signed attestation: "peer X saw this branch state at
time T."

### Peer track record

Each signed merge is a verifiable act of service — the
peer fetched, validated consensus, and committed. The
merge history is countable:

```bash
git log --grep='Freechains-Peer: <key>'
```

A peer's merge count is a measure of participation and
reliability, independent of authoring content. Unlike
author reputation (which flows from likes), peer
reputation is earned by doing work that is costly to
fake — you must actually fetch and validate.

---

## 3. Peer Trust Levels

| Peer type | config/ | chains/               |
|-----------|---------|-----------------------|
| Owner     | sync    | git push/fetch+merge  |
| Other     | never   | freechains rules      |

Owner peers share the same key material — full trust, no
validation, no consensus checks. See replication.md.

Non-owner peers require signature verification, reputation
checks, and size limits before accepting content.

---

## 4. Sync Topology

### Pairwise sync

Sync is always between exactly two peers (fetch + merge).
There is no broadcast or gossip layer — propagation
happens transitively through pairwise sync.

```
A ↔ B ↔ C     A syncs with B, B syncs with C
                → A's content reaches C via B
```

### Transport options

- **git daemon** (`git://`): anonymous, fast, no auth.
  Direct peer-to-peer. Requires knowing the peer's IP.
- **GitHub/GitLab**: relay for peers behind NAT. Push
  requires auth (not permissionless). See network.md.
- **Self-hosted GitLab**: removes auth/centralization
  problems. Acts as always-on seed node.

### Sync flow

```bash
git fetch <remote> <branch>
# validate fetched commits (signatures, rep, DAG rules)
git merge --no-edit --no-ff FETCH_HEAD
```

Never use `git pull` — it merges before validation.
See replication.md, consensus.md.

---

## 5. Owner-Driven Fork Resolution

### The problem: choosing sides in a fork

When branches X and Y diverge, neutral peers C and D
can't decide which side to follow from content alone.
Prefix reputation is symmetric (same for both sides),
suffix content is subjective (each side has different
posts). The decision "which side am I on?" is social,
not algorithmic.

### The solution: owner's vote

Each local repo has an **owner** — the peer's signing
key. When a branch divergence triggers voting (merge.md):

1. Authors in the common prefix vote for X or Y, weighted
   by their prefix reputation
2. If the vote difference crosses the threshold → hard
   fork (chain splits into two identities)
3. Each peer follows its **owner's vote** — the local
   repo's signing key determines the side
4. Peers who didn't vote follow the majority (consensus
   rule)

This eliminates the coalition problem for fork decisions:
no peer group negotiation needed. The owner's identity
is the tiebreaker.

### Relationship to coalitions

Coalitions (peer groups that commit to regular sync) are
still useful for **isolation detection** and **witness
timestamps**, but are no longer needed for fork resolution.
The vote mechanism handles forks directly:

- **Before**: coalitions were proposed as the mechanism
  for peers to agree on which side of a fork to follow
- **After**: the owner's vote resolves this. Coalitions
  remain useful for operational health (detecting
  isolation, ensuring sync liveness), not for consensus
  decisions

### Coalitions as operational infrastructure (NOT REVIEWED)

Coalitions may still be valuable for:

1. **Isolation detection**: if a peer can't reach any
   coalition member for N hours, alert the user
2. **Witness timestamps**: merge is "settled" when M-of-N
   coalition members have seen it
3. **Checkpoint quorum**: checkpoint commits (7-day.md)
   need a quorum of distinct authors — coalition provides
   the expected quorum set

Open questions from the original coalition proposal
(formation, size, incentives, sybil resistance) remain
relevant for this operational role but are less critical
now that fork resolution is handled by owner votes.

---

## Related Plans

- [replication.md](replication.md) — Owner sync workflow
- [network.md](network.md) — Transport options (git daemon,
  GitHub, Radicle)
- [trailer.md](trailer.md) — `Freechains-Peer:` trailer
- [merge.md](merge.md) — Merge semantics and voting
- [7-day.md](7-day.md) — 7-day rule and checkpoint commits
- [threats.md](threats.md) — T1 partition fork, T2a
  merge-witness timestamps
- [consensus.md](consensus.md) — Fetch validation pipeline
