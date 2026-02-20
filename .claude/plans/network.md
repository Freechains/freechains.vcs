# Network: Radicle & GitHub/GitLab

## Radicle

Radicle is the closest existing project to "Freechains built on git" — a p2p code collaboration stack using git's object model + a gossip protocol + cryptographic identities.

### Why NOT use Radicle for Freechains

| Problem | Detail |
|---|---|
| Wrong domain | Built for code collaboration, not general content dissemination |
| No Lua bindings | Written in Rust, no Lua API |
| Opinionated gossip | Peer discovery tightly coupled to Radicle's identity system, not extractable |
| No reputation model | Social layer uses CRDTs (merge-friendly), not reputation-based ordering |
| Heavy | Full Radicle node is significant infrastructure |

### Why USE Radicle (or learn from it)

| Benefit | Detail |
|---|---|
| Transport solved | Peer discovery, NAT traversal, gossip propagation already built |
| Self-certifying identities | All actions cryptographically signed, verifiable without trusted third party |
| Proven at scale | Gossip + git combination works in production |
| Validates the approach | Proof that git + gossip + crypto identity works |
| Collaborative Objects | CRDTs stored inside git — shows git can hold structured social data |

**Verdict**: Radicle validates the architecture but is the wrong tool. Freechains is its own protocol with a different purpose. Build on raw git + your own gossip layer.

---

## GitHub / GitLab as a Node

### What you get

| Feature | Detail |
|---|---|
| Storage | Stores git objects (blobs, commits, trees) exactly as designed |
| Sync relay | Any peer can push/pull through it — relay for peers behind NAT |
| Availability | ~100% uptime, global CDN, free |
| No infrastructure | No servers to run, no ports to open |

### Limitations

| Limitation | Detail |
|---|---|
| Not a Freechains node | Can't run consensus or compute reputation — pure git remote |
| Push requires auth | Every peer needs a GitHub account — breaks permissionless model |
| Rate and size limits | Push rate limits; ~1GB soft repo size limit; 100MB per file |
| Centralization risk | Account can be banned, repo taken down — single point of failure |
| No anonymous push | `git://` is read-only; push always requires credentials |
| UI mismatch | Commit messages full of hashes/signatures look like garbage in the interface |
| No hooks on push | GitHub Actions can approximate `post-receive` but is not the same |

### Practical architecture

```
peer A <--git push/pull--> GitHub/GitLab <--git push/pull--> peer B
  ^                                                            ^
  +------------------ direct git daemon ----------------------+
```

GitHub/GitLab acts as a **bootstrap / seed relay** for peers behind NAT or for initial discovery. Peers that know each other's IPs use `git daemon` directly — anonymous, fast, no auth.

### Self-hosted GitLab changes the picture

Removes account/auth/centralization problems entirely. You control the server, can enable anonymous push, no rate limits, no takedown risk. A self-hosted GitLab instance becomes a proper Freechains seed node — always on, stores all blocks, reachable by any peer. Hooks work fully. Much closer to the `freechains-host` model.
