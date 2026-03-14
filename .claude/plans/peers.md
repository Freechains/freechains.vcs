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

Every merge commit carries a `Freechains-Peer: <pubkey>`
trailer identifying the peer that performed the sync.
Combined with GPG signing, this is a signed attestation.

See [trailer.md](trailer.md) for trailer format and
peer reputation details.

---

## 3. Peer Trust Levels

See [replication.md](replication.md) for the full
owner/non-owner trust table and sync rules.

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

## 5. Peer Coalitions (NOT REVIEWED)

### The problem: 7-day isolation attack

The 7-day rule (see 7-day.md) protects against offline
reputation farming: if a branch has been active past the
threshold, remote content can never reorder local history.

But a single peer is vulnerable:
- An isolated peer doesn't know it's isolated
- An attacker controlling the peer's only sync partner
  can feed it a crafted branch
- A peer that goes offline for 7+ days returns to find
  its local branch frozen — other peers may have moved on

### The idea: peer groups

Peers form **coalitions** — small groups that commit to
syncing with each other regularly. A coalition provides:

1. **Isolation detection**: if a peer can't reach ANY
   coalition member for N hours, it knows it might be
   isolated and can act defensively (refuse merges from
   unknown peers, pause posting, alert the user)

2. **Witness timestamps**: coalition members witness each
   other's merges. A merge is only considered "settled"
   when M-of-N coalition members have seen it (created
   their own merge commits on top). This is the
   merge-witness timestamp idea from threats.md, but
   with a defined witness set.

3. **7-day defense**: a coalition that stays connected
   never has branches diverge past the 7-day threshold.
   The attack requires isolating the **entire coalition**,
   not just one peer. Cost scales with coalition size.

4. **Checkpoint quorum**: checkpoint commits (see 7-day.md)
   require a quorum of distinct authors. A coalition
   provides a natural quorum set — the peers who are
   expected to post checkpoints.

### How it could work

- A coalition is a set of public keys, stored in the
  chain's metadata or in a well-known commit
- Coalition membership is visible in the DAG (signed
  commits from coalition members)
- A peer joining a coalition commits to syncing at least
  once per interval (e.g., every 6 hours)
- If a coalition member goes silent for too long, the
  others notice and can warn users

### Relationship to checkpoint commits

Checkpoint commits (7-day.md) are a specific mechanism;
coalitions are the social structure that makes them work:

- **Without coalitions**: any peer can post a checkpoint,
  but there's no expectation of coverage. Lazy or offline
  peers mean no quorum forms.
- **With coalitions**: members are expected to post
  checkpoints. Failure to do so is visible and
  actionable — the coalition can exclude the peer.

### Relationship to merge voting

Merge voting (merge.md §4) lets the community reject a
bad merge. Coalitions complement this:

- Coalition members are the **first responders** — they
  see the merge first and can vote immediately
- A coalition's collective vote carries weight because
  they are known, active participants
- If a coalition member performed the bad merge, the
  other members can vote it down and stop syncing with
  that peer

### Open questions (NOT REVIEWED)

1. **Formation**: How do peers discover and join
   coalitions? Is it manual (out-of-band agreement) or
   on-chain (a "join" commit)?

2. **Size**: What's the minimum viable coalition? 3 peers
   (basic Byzantine tolerance)? 5? Too large and
   coordination overhead grows.

3. **Incentives**: What motivates peers to stay in a
   coalition and sync regularly? Reputation rewards for
   merge activity? Penalties for going silent?

4. **Multiple coalitions**: Can a peer belong to multiple
   coalitions? Can coalitions overlap? What happens when
   two coalitions disagree?

5. **Enforcement**: Is coalition membership enforced by
   the protocol or just a social convention? If protocol-
   enforced, it needs on-chain representation.

6. **Sybil coalitions**: An attacker could create a
   coalition of sockpuppets. Coalition membership alone
   doesn't prove independence — it needs to be combined
   with reputation or identity verification.

7. **Relationship to pioneers**: Pioneers already form a
   natural initial coalition (they all start with 30/N
   rep). Should the coalition mechanism be an extension
   of the pioneer concept?

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
