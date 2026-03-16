# Git for Social Networks & Consensus

## Overview

Landscape analysis of projects and academic work using Git
as a foundation for decentralized social networks, consensus
mechanisms, and distributed content systems.
Positions Freechains within this space.

## Status: Research

## Academic Framing: Feig 2018

**Paper:** Ephraim Feig, *"A Framework for Blockchain-Based
Applications"*, arXiv:1803.00892, March 2018.

Central claim: **Git is already a blockchain**, operating
under a completely different trust model than Bitcoin.

Key arguments:
- Every Git branch is a blockchain (commits = blocks,
  cryptographically linked via SHA hashes)
- Bitcoin consensus = automatic, PoW-based, trust-free
- Git consensus = social, hierarchical, **trust-based** —
  a form of "Proof of Stake where the stake is reputation +
  commit history + permission level"
- Different applications need different trust models

Feig's 10 design questions for blockchain systems:
1. Who are the users?
2. What data do users input?
3. Are any inputs irreversible?
4. Who are the peers?
5. How do peers create blocks?
6. What do peers validate?
7. How do peers validate?
8. How do peers reach consensus?
9. Is the blockchain immutable?
10. How are peers incentivized?

**Relevance to Freechains:** Legitimizes the design space
between "trustless PoW" and "fully centralized."
Freechains sits in this middle space — trust-augmented by
economic incentives, not pure social trust.

## The Fundamental Problem: Canonicity

Central challenge: **who decides what HEAD is?**

In Git, there is no protocol-level answer.
Canonicity is social: whoever controls `origin/master` wins.
Fine for software development (there is a maintainer), but
breaks for leaderless social networks needing convergence
without central authority.

### What Git Lacks as a Consensus Mechanism

- No HEAD election protocol
- No fork resolution rule (unlike Bitcoin's "longest chain")
- Mutable refs (`rebase`/`force-push` can rewrite history)
- No Sybil resistance (anyone can fork and push garbage)

## Known Projects

### Radicle (radicle.xyz)

**Status:** Most mature; v1.0 launched March 2024.

- **No canonical global truth** — each repo is sovereign;
  each user has their own fork
- **Social artifacts as Git objects** — issues, patches,
  comments stored as *Collaborative Objects (COBs)*,
  signed with ed25519 keys
- **Gossip protocol (Heartwood)** for peer/repo discovery
- **No consensus on HEAD** — bazaar model: many upstreams,
  patches flow between them, users choose which fork
- Inspired by Secure Scuttlebutt (SSB) and Bitcoin LN
- Signing operates at the refs level (sigrefs), not by
  modifying commit hashes

**Limitation:** Pushes the consensus problem to the social
layer.
Cannot build a shared global feed without external
coordination.

### Git Consensus (git-consensus.github.io)

**Status:** Active project (Ethereum/Solidity contracts).

- Converts Git's informal ownership into a formal **DAO
  on Ethereum**
- Each repo maps to an **ERC20 token contract**
  (token balance = voting power)
- Commits earn newly minted tokens → contributors become
  stakeholders automatically
- Releases (tags) require on-chain approval
- Self-reinforcing: contribute → earn tokens → gain voting
  power → vote on releases

**Note:** Specifically about project governance, not general
social content.
Git is input data; Ethereum is the consensus mechanism.

### Gitchain (Cardstack, 2019)

**Status:** Archived/deprecated.

- Git as **Layer 2** application state layer
- Git stores data (packfiles); Ethereum stores canonical
  pointers to packfiles
- Packfiles in distributed storage (S3, IPFS); blockchain
  stores reference
- Chain-agnostic architecture (pluggable adapters)

**Limitation:** Depends on external consensus for global
truth.

### ForgeFed / Forgejo Federation

- W3C/ActivityPub-based federation protocol for forges
  (Gitea, Forgejo)
- Social layer is ActivityPub; Git is just content transport
- Federated but not P2P — still relies on servers

### git-bug

- Embeds bug tracking (issues, comments) directly into
  Git objects (no extra files)
- Offline-first, no network consensus
- Demonstrates Git-as-social-data pattern but is not a
  network protocol

### git-ssb

- Combines Secure Scuttlebutt (SSB) with Git
- Hosts Git repos over SSB's append-only log
- More SSB-native than Git-native

### Fossil SCM

- Monolithic alternative to Git; includes wiki, forum,
  tickets in same repo
- Single-file distributed database
- No P2P consensus; central repo authority still assumed

## Comparative Analysis

| Approach        | Git provides      | Consensus        | Global truth? | Spam resistance    |
|-----------------|-------------------|------------------|---------------|--------------------|
| Feig (2018)     | blockchain struct | social/hier.     | single repos  | social gatekeeping |
| Radicle         | storage + gossip  | social (upstream)| no            | none (protocol)    |
| Gitchain        | storage layer     | Ethereum         | yes (external)| token cost         |
| Git Consensus   | contrib. history  | ERC20 votes      | yes (Ethereum)| token cost         |
| ForgeFed        | content transport | ActivityPub fed. | per-server    | server moderation  |
| git-bug         | social data model | none (local)     | no            | N/A                |
| **Freechains**  | DAG + transport   | like/dislike rep | per-chain     | native economic    |

## Key Insights

### 1. The Spectrum of Trust Models

Feig (2018) establishes that "blockchain" spans a spectrum
from trustless (Bitcoin PoW) to fully trust-based (Git
social consensus).
All projects occupy different points.
Freechains sits between them: trust-augmented by economic
incentives rather than pure social gatekeeping or external
token chains.

### 2. Canonicity Is the Core Unsolved Challenge

Every Git-native social project either:
- (a) avoids global canonicity by design (Radicle's bazaar)
- (b) outsources it to an external blockchain (Gitchain,
  Git Consensus)
- (c) relies on a central server (ForgeFed, Fossil)

None provide a **protocol-native** solution to fork
resolution for permissionless social content.

### 3. Radicle's Signing Approach Is Instructive

Radicle keeps source code commit hashes independent of
signatures — signing operates at the refs level (sigrefs).
COBs sign each modification as a Git commit but the hash
excludes the signature per standard Git conventions.
Most mature solution to Git's "signatures change hashes"
impedance mismatch.

### 4. The Gap Freechains Addresses

None of the surveyed projects provide **protocol-level spam
resistance or reputation scoring** without an external
blockchain or social gatekeeping:
- Radicle: spam filtering via social following (manual)
- Gitchain/Git Consensus: anti-spam via Ethereum token costs
- Freechains: reputation natively in the DAG via like/dislike

This is Freechains' genuinely novel contribution: a Git-like
DAG with a **built-in economic layer** replacing the social
trust Git implicitly relies on.

### 5. Academic Framing for Freechains

> A content-addressed DAG (Git-like) with protocol-native
> reputation scoring (like/dislike token economics) that
> replaces the implicit social trust of Git-based systems
> and the explicit token costs of blockchain-based systems
> — enabling permissionless, spam-resistant, decentralized
> messaging without external consensus infrastructure.

## References

- Feig, E. (2018). *A Framework for Blockchain-Based
  Applications*. arXiv:1803.00892.
  https://arxiv.org/abs/1803.00892
- Radicle Protocol Guide.
  https://radicle.xyz/guides/protocol
- Git Consensus Documentation.
  https://git-consensus.github.io/docs/
- Gitchain (Cardstack).
  https://medium.com/cardstack/introducing-gitchain-add61790226e
- ForgeFed. https://forgefed.org/
- Ferrin, D. (2016). *Is a Git Repository a Blockchain?*
  https://medium.com/@shemnon/is-a-git-repository-a-blockchain-35cb1cd2c491

## TODO

- [ ] Answer Feig's 10 questions for Freechains
- [ ] Study Radicle's sigrefs signing model in detail
- [ ] Evaluate if Radicle's COBs pattern applies to chains
- [ ] Write positioning paper / README section
