# Freechains + Git: Conversation Summary

## 1. Data Structure Relationships

The conversation started from a unified perspective on related data structures:

- **Append-only logs** are the primitive — never overwrite, only grow
- **Immutability** enables content addressing: a value's hash becomes its identity
- **Merkle Trees** apply content addressing recursively — the root hash fingerprints the entire structure, enabling O(log n) proofs and efficient diffing
- **Blockchains** are a Merkle hash chain + append-only log + distributed consensus
- **CRDTs** solve a different problem: merging concurrent writes without coordination, often implemented on top of append-only op logs

All of them share the same root insight: **trust through structure, not through authority**.

---

## 2. Database Options Considered

| Goal | Best Option |
|---|---|
| Append-only log + queryability | PostgreSQL (event sourcing) |
| High-throughput log | Kafka |
| Content-addressed blobs | IPFS or hash-keyed SQLite |
| Distributed sync without coordination | ElectricSQL / Ditto |
| Embedded, zero infrastructure | SQLite |

---

## 3. Git as the Database for Freechains

### Data model mapping

| Freechains | Git |
|---|---|
| Block hash | Commit hash |
| Block parents | Commit parents |
| **Chain** | **Repository** (not branch — each chain is independent) |
| Consensus order | `git log --date-order` |
| Payload | Blob object |
| Fork/merge | Merge commit |

**Chain = Repository, not Branch.** Not all peers are interested in all chains. If chains were branches in a shared repo, a sync would pull all chains at once. Instead, each chain is its own git repository — peers clone only the repos they care about. Syncing one chain has zero effect on others. This also makes `git clone` a near-perfect match for `chains join`.

### DAG Traversal and Consensus

`git log` offers two relevant orderings:

- **`--topo-order`**: groups branches together, no guaranteed deterministic tiebreaker for concurrent commits — **not suitable** for consensus
- **`--date-order`**: respects parent/child relationships AND uses committer timestamp as tiebreaker — **deterministic** across peers since timestamps are embedded in the immutable commit object

Since committer timestamps are part of the commit object (not read from the local clock at traversal time), two peers with identical commit objects will produce identical `--date-order` output. This makes `--date-order` the closer analog to Freechains' consensus traversal — though Freechains still needs its own rule on top for reputation-based ordering.

### Fast-forward vs True Merge

- **Fast-forward** (no commit, no editor): branch being merged into is a direct ancestor — git just moves the pointer. The degenerate single-writer case.
- **True merge** (new commit, editor opens): both branches have diverged — git creates a new DAG node with two parents. This is the normal Freechains case: every block can have multiple parents because the network is never synchronized enough for one peer to always be a clean ancestor of another.

### Git Daemon and Peer Sync

`git daemon` is a minimal TCP server (port 9418) that serves git objects. Sync works in two phases:

1. **Ref advertisement**: peers exchange head hashes to find what's missing
2. **Packfile transfer**: minimal set of objects packed and sent

Freechains' `send`/`recv` is also client-server — one peer explicitly connects to another. Both models are point-to-point. The "p2p" aspect of Freechains is that there is no privileged central node; any peer can be client or server. Individual connections are structurally identical to `git push` / `git fetch`.

### Merge after every sync — single HEAD model

In original Freechains, the DAG can have **multiple heads** — you only merge (produce a new block with multiple parents) when you post. Between posts, concurrent blocks from different peers sit as parallel heads.

With git, after `git fetch` you have `FETCH_HEAD` diverging from local `HEAD`. Git requires an explicit merge to integrate. This means:

**You must merge after every sync, even if you are not posting.**

This is a behavioral difference from original Freechains, but actually a **simplification**:

- There is always exactly **one HEAD** per chain-repo at any point
- The merge commit records "I have seen and integrated all blocks up to this point"
- The DAG structure is preserved — the merge commit has multiple parents just like a Freechains block
- Consensus traversal starts from a single, unambiguous HEAD rather than finding and reconciling multiple heads

The tradeoff: sync-only merge commits carry no payload. These should be marked with a `freechains-sync: true` extra header so the consensus algorithm can skip them when computing the content list.

---

## 4. Git Commit Object Fields

| Field | In Hash | Actual Content | Purpose | Required |
|---|---|---|---|---|
| `tree` | ✅ | SHA of root tree object | Points to full file snapshot (indirect payload) | ✅ |
| `parent` | ✅ | SHA(s) of parent commit(s) | DAG links to prior commits | ❌ absent on root commit |
| `author name` | ✅ | Free text string | Who wrote the change | ✅ |
| `author email` | ✅ | Free text string | Author contact / identity | ✅ |
| `author date` | ✅ | Unix timestamp + timezone | When change was originally written | ✅ |
| `committer name` | ✅ | Free text string | Who applied/created the commit | ✅ |
| `committer email` | ✅ | Free text string | Committer contact / identity | ✅ |
| `committer date` | ✅ | Unix timestamp + timezone | When commit was created — used by `--date-order` | ✅ |
| `message` | ✅ | Free text string, any length | Human description — **can hold signature data** | ✅ (can be empty) |
| `encoding` | ✅ | Charset string e.g. `UTF-8` | Character encoding of message | ❌ |
| `extra headers` | ✅ | Free text key-value lines | Custom metadata — **cleanest place for Freechains signature** | ❌ |
| `gpg signature` | ❌ | Armored PGP/SSH blob | Authorship verification — **outside the hash** | ❌ |
| `mergetag` | ❌ | Raw embedded tag object | Signed merge metadata — **outside the hash** | ❌ |
| blob (payload) | ✅ indirect | Raw bytes, any content | Actual file/post content, reached via tree reference | via tree |

### Key observations

- **Author/committer name and email are free text** — no validation; a public key can go there
- **GPG signature is outside the hash** — this is why git signing is fragile for trustless systems
- **Extra headers are inside the hash** — cleanest place for `freechains-pubkey` / `freechains-sig`
- **Blob is pure content** — no filename, no metadata (see section 5)

---

## 5. Git Blob vs Freechains Payload

A git blob is **content only** — the filename lives in the tree, not the blob. Perfect match for Freechains' payload model:

| Property | Git blob | Freechains payload |
|---|---|---|
| Content addressed | ✅ hash of contents | ✅ hash of contents |
| No filename stored | ✅ filename lives in tree | ✅ no filename concept |
| No metadata | ✅ pure bytes | ✅ pure bytes |
| Same content = same hash | ✅ | ✅ |
| Binary safe | ✅ | ✅ |
| Deduplicated automatically | ✅ same content → same hash → stored once | ✅ |

The blob is the one place in git's object model with a **perfect 1:1 match** to Freechains. Both are dumb content stores. The structured envelope around them (tree/commit in git, block in Freechains) is where identity, authorship, and DAG links live.

---

## 6. Freechains Commands → Git Mapping

| Freechains Command | Git Equivalent | Match (1–5) | Notes |
|---|---|---|---|
| `freechains-host start <dir>` | `git init` + `git daemon` | 3 | init is close; daemon is a separate persistent process |
| `freechains chains join <chain>` | `git clone` | 4 | each chain is its own repo; cloning = joining |
| `freechains chains leave <chain>` | delete local repo + `git remote remove` | 3 | git has no single command for this |
| `freechains chains list` | `ls` of cloned repos | 3 | no native multi-repo listing in git |
| `freechains chain <n> genesis` | `git rev-list --max-parents=0 HEAD` | 4 | finding root commit, very close |
| `freechains chain <n> heads` | `git rev-parse HEAD` | 4 | single HEAD model simplifies this to one command |
| `freechains chain <n> get block <hash>` | `git cat-file -p <hash>` | 5 | direct content-addressed lookup, perfect |
| `freechains chain <n> get payload <hash>` | `git cat-file blob <hash>` | 5 | blob = payload, perfect match |
| `freechains chain <n> post inline <text>` | `git hash-object` + `git commit` | 3 | must write blob + tree before committing |
| `freechains chain <n> like <hash>` | no equivalent — zero-payload commit with `freechains-like: <hash>` extra header | 1 | stored as structural commit with metadata only |
| `freechains chain <n> dislike <hash>` | no equivalent — zero-payload commit with `freechains-dislike: <hash>` extra header | 1 | same pattern as like |
| `freechains chain <n> reps <hash_or_pub>` | no equivalent — walk `git log`, accumulate like/dislike headers, cache in SQLite | 1 | computed state, not stored in git |
| `freechains chain <n> consensus` | `git log --date-order` skipping sync commits | 3 | deterministic but not the same rule; skip `freechains-sync: true` commits |
| `freechains chain <n> listen` | `post-receive` git hook on server | 3 | fires server-side after every push; see hook table below |
| `freechains peer <addr> ping` | `git ls-remote <remote>` | 2 | tests reachability but does much more |
| `freechains peer <addr> chains` | `ls` of repos served by remote `git daemon` | 2 | no standard discovery protocol in git |
| `freechains peer <addr> send <chain>` | `git push` | 4 | strong match, both client-server |
| `freechains peer <addr> recv <chain>` | `git fetch` + `git merge` | 4 | fetch alone not enough — must merge to integrate; always produces a merge commit |
| `freechains keys shared <passphrase>` | no equivalent — use libsodium `crypto_secretbox_keygen` via luasodium | 1 | implement in Lua |
| `freechains keys pubpvt <passphrase>` | no equivalent — use libsodium `crypto_sign_keypair` via luasodium | 1 | implement in Lua |

### Git Hooks

Git hooks are shell scripts executed automatically at specific points in git's workflow. They live in `.git/hooks/`. Relevant hooks for Freechains:

| Hook | Runs when | Side | Use for Freechains |
|---|---|---|---|
| `post-receive` | After a `git push` is received and written | **Server** | Trigger consensus recomputation, notify listeners — closest analog to `chain listen` |
| `pre-receive` | Before objects are written on push | **Server** | Validate block signatures before accepting — reject invalid blocks |
| `update` | Once per ref being updated on push | **Server** | Per-chain signature validation |
| `post-merge` | After a `git merge` completes locally | **Client** | Trigger SQLite reputation cache update |
| `post-commit` | After a local commit | **Client** | Trigger local consensus refresh |

`post-receive` is the key one — it fires on the server side every time a peer pushes, which is exactly when new blocks arrive. Combined with `pre-receive` for signature validation, you get the full Freechains block acceptance pipeline as git hooks.

---

## 7. Signing: Git vs Freechains

| | Git | Freechains |
|---|---|---|
| Signing | Optional, external (GPG/SSH) | Structural, integral |
| Key management | External (`gpg`, `ssh-keygen`) | Built-in (`freechains keys`) |
| Identity | Email + key, loosely coupled | Public key **is** the identity |
| Unsigned content | Fully valid | Valid only on public chains |
| Signature affects hash | ❌ outside the hash | ✅ inside the hash |
| Impersonation difficulty | Trivial (free text name/email) | Impossible (hash includes pubkey) |

### Why git's model is not fragile for its use case

Git's trust anchor is **the channel, not the data**. When you pull from `kernel.org`, trust comes from SSH authentication and server access controls — not from commit metadata. Rewriting history is detectable because hashes of all subsequent commits change, visible to everyone on next fetch. This would be fragile for Freechains because Freechains has **no trusted infrastructure** — the only thing peers can trust is the math.

### Where to embed Freechains signature in a git commit

| Option | In Hash | API ease | Human-readable log | Verdict |
|---|---|---|---|---|
| Commit message | ✅ | ✅ easy | ❌ ugly | good, simple |
| Extra headers | ✅ | ⚠️ raw object construction needed | ✅ preserved | best, cleanest |
| Author/committer fields | ✅ | ✅ | ⚠️ pubkey as name, awkward | works but hacky |
| GPG signature field | ❌ | ✅ | ✅ | wrong — outside hash |
| Git notes | ❌ | ✅ | ✅ | wrong — outside hash |

Recommended: **extra headers** (`freechains-pubkey`, `freechains-sig`) keep the message human-readable and put all cryptographic data inside the hash. Requires constructing raw commit objects but gives the cleanest separation.

---

## 8. Radicle

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

## 9. GitHub / GitLab as a Node

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
peer A ←—git push/pull—→ GitHub/GitLab ←—git push/pull—→ peer B
  ↑                                                          ↑
  └——————————————— direct git daemon ———————————————————————┘
```

GitHub/GitLab acts as a **bootstrap / seed relay** for peers behind NAT or for initial discovery. Peers that know each other's IPs use `git daemon` directly — anonymous, fast, no auth.

### Self-hosted GitLab changes the picture

Removes account/auth/centralization problems entirely. You control the server, can enable anonymous push, no rate limits, no takedown risk. A self-hosted GitLab instance becomes a proper Freechains seed node — always on, stores all blocks, reachable by any peer. Hooks work fully. Much closer to the `freechains-host` model.

---

## 10. SQLite as a Companion Store

Git is excellent at DAG storage and sync, but **not at running queries or caching computed state**. SQLite fills that gap cleanly.

### What SQLite stores (and git doesn't)

```sql
-- Cached consensus linearization
-- Recomputed after each git fetch+merge, cheaply invalidated
CREATE TABLE consensus (
    chain    TEXT,
    position INTEGER,
    hash     TEXT,
    PRIMARY KEY (chain, position)
);

-- Cached reputation state at a known commit (checkpoint)
-- Avoids replaying from genesis on every sync
CREATE TABLE rep_checkpoint (
    chain       TEXT,
    at_hash     TEXT,   -- git commit hash this was computed at
    author_pub  TEXT,
    reps        INTEGER,
    PRIMARY KEY (chain, author_pub)
);
```

### The workflow

```
git fetch + git merge  →  post-merge hook fires
                       →  detect new commits (rev-list old..new)
                       →  skip freechains-sync commits
                       →  walk remaining commits in date-order
                       →  apply reputation deltas from checkpoint
                       →  update rep_checkpoint
                       →  recompute consensus order
                       →  overwrite consensus table
```

### Why not store everything in git

- Reputation is a **running aggregate** — the result of replaying history. Git has no concept of memoizing intermediate computation.
- Querying `SELECT * FROM consensus ORDER BY position` is instant. Walking `git log` for every read is not.
- The consensus table is a **write-through cache**: cheap to invalidate, fast to read.
- If SQLite is deleted, it can be fully reconstructed by replaying git history — git is always the source of truth.

### The clean separation

| Concern | Tool |
|---|---|
| Block payload storage | Git blob |
| DAG structure | Git commit graph |
| Peer sync | Git push/fetch + merge / git daemon |
| Block validation on receive | `pre-receive` git hook |
| Post-sync processing trigger | `post-merge` / `post-receive` git hook |
| Bootstrap / relay | GitHub (public) or self-hosted GitLab |
| Consensus cache | SQLite |
| Reputation checkpoint | SQLite |
| Application / consensus logic | Lua |

---

## 11. Filesystem Layout

Bare repos (no working tree) are the right choice for storage — same as how `git daemon` and GitLab serve repos. A bare repo has no checked-out files, just the git internals, which is all a Freechains node needs.

### Per-user (XDG compliant)

```
~/.local/share/freechains/        ← XDG_DATA_HOME
  chains/
    <chain-hash>/                 ← bare git repo (DAG + blocks)
    <chain-hash>.db               ← SQLite cache (consensus + rep checkpoint)
    @francisco -> <chain-hash>/   ← symlink alias (human-readable name)
    #sports    -> <chain-hash>/   ← symlink alias
    $friends   -> <chain-hash>/   ← symlink alias
  keys/
    <pubkey>.pub                  ← public key
    <pubkey>.key                  ← encrypted private key

~/.config/freechains/             ← XDG_CONFIG_HOME
  config.toml                     ← host port, default peers, key to use
```

### Global / system node (seed node)

```
/var/lib/freechains/              ← FHS: persistent application data
  chains/
    <chain-hash>/                 ← bare git repo
    <chain-hash>.db               ← SQLite cache
  peers.conf                      ← known peers registry
```

### Chain naming and aliases

Symlinks give human-readable names while actual storage is content-addressed, mirroring Freechains' own naming convention (`@pubkey`, `#topic`, `$private`):

| Symlink name | Meaning |
|---|---|
| `@<pubkey>` | Single-author identity chain |
| `#<topic>` | Public topic chain |
| `$<name>` | Private shared chain |

The `.db` SQLite file sits adjacent to its bare repo — easy to identify, easy to delete and rebuild for a specific chain without touching others. If the `.db` is deleted, it can be fully reconstructed by replaying the git history in the adjacent repo.

---

## 12. Lua Libraries

| Purpose | Library | Notes |
|---|---|---|
| Git (official) | [libgit2/luagit2](https://github.com/libgit2/luagit2) | Full libgit2 API, requires C compilation |
| Git (LuaJIT FFI) | [luapower/libgit2](https://github.com/luapower/libgit2) | No compilation, pure FFI |
| SQLite | [lsqlite3](https://luarocks.org/modules/dougcurrie/lsqlite3) | Standard binding |
| SQLite (bundled) | lsqlite3complete | Bundles SQLite amalgamation — zero external deps |
| Crypto (libsodium) | [luasodium](https://github.com/luasodium/luasodium) | Key generation replacing `freechains keys` |
| Freechains Lua client | [Freechains/lua](https://github.com/Freechains/lua) | Official Lua repo |
| Freechains Lua wrapper | [micahkendall/freechains-lua](https://github.com/micahkendall/freechains-lua) | OOP wrapper over CLI |

For a full comparison of crypto tool alternatives (openssl, luasodium, age, gpg, etc.), see `crypto.md`.
