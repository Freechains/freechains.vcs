# Git as the Database for Freechains

## Data model mapping

| Freechains | Git |
|---|---|
| Block hash | Commit hash |
| Block parents | Commit parents |
| **Chain** | **Repository** (not branch — each chain is independent) |
| Consensus order | `git log --date-order` |
| Payload | Blob object |
| Fork/merge | Merge commit |

**Chain = Repository, not Branch.** Not all peers are interested in all chains. If chains were branches in a shared repo, a sync would pull all chains at once. Instead, each chain is its own git repository — peers clone only the repos they care about. Syncing one chain has zero effect on others. This also makes `git clone` a near-perfect match for `chains join`.

## DAG Traversal and Consensus

`git log` offers two relevant orderings:

- **`--topo-order`**: groups branches together, no guaranteed deterministic tiebreaker for concurrent commits — **not suitable** for consensus
- **`--date-order`**: respects parent/child relationships AND uses committer timestamp as tiebreaker — **deterministic** across peers since timestamps are embedded in the immutable commit object

Since committer timestamps are part of the commit object (not read from the local clock at traversal time), two peers with identical commit objects will produce identical `--date-order` output. This makes `--date-order` the closer analog to Freechains' consensus traversal — though Freechains still needs its own rule on top for reputation-based ordering.

## Fast-forward vs True Merge

- **Fast-forward** (no commit, no editor): branch being merged into is a direct ancestor — git just moves the pointer. The degenerate single-writer case.
- **True merge** (new commit, editor opens): both branches have diverged — git creates a new DAG node with two parents. This is the normal Freechains case: every block can have multiple parents because the network is never synchronized enough for one peer to always be a clean ancestor of another.

## Git Daemon and Peer Sync

`git daemon` is a minimal TCP server (port 9418) that serves git objects. Sync works in two phases:

1. **Ref advertisement**: peers exchange head hashes to find what's missing
2. **Packfile transfer**: minimal set of objects packed and sent

Freechains' `send`/`recv` is also client-server — one peer explicitly connects to another. Both models are point-to-point. The "p2p" aspect of Freechains is that there is no privileged central node; any peer can be client or server. Individual connections are structurally identical to `git push` / `git fetch`.

## Merge after every sync — single HEAD model

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

## Git Commit Object Fields

| Field | In Hash | Actual Content | Purpose | Required |
|---|---|---|---|---|
| `tree` | yes | SHA of root tree object | Points to full file snapshot (indirect payload) | yes |
| `parent` | yes | SHA(s) of parent commit(s) | DAG links to prior commits | no (absent on root commit) |
| `author name` | yes | Free text string | Who wrote the change | yes |
| `author email` | yes | Free text string | Author contact / identity | yes |
| `author date` | yes | Unix timestamp + timezone | When change was originally written | yes |
| `committer name` | yes | Free text string | Who applied/created the commit | yes |
| `committer email` | yes | Free text string | Committer contact / identity | yes |
| `committer date` | yes | Unix timestamp + timezone | When commit was created — used by `--date-order` | yes |
| `message` | yes | Free text string, any length | Human description — **can hold signature data** | yes (can be empty) |
| `encoding` | yes | Charset string e.g. `UTF-8` | Character encoding of message | no |
| `extra headers` | yes | Free text key-value lines | Custom metadata — **cleanest place for Freechains signature** | no |
| `gpg signature` | **no** | Armored PGP/SSH blob | Authorship verification — **outside the hash** | no |
| `mergetag` | **no** | Raw embedded tag object | Signed merge metadata — **outside the hash** | no |
| blob (payload) | yes (indirect) | Raw bytes, any content | Actual file/post content, reached via tree reference | via tree |

### Key observations

- **Author/committer name and email are free text** — no validation; a public key can go there
- **GPG signature is outside the hash** — this is why git signing is fragile for trustless systems
- **Extra headers are inside the hash** — cleanest place for `freechains-pubkey` / `freechains-sig`
- **Blob is pure content** — no filename, no metadata

---

## Git Blob vs Freechains Payload

A git blob is **content only** — the filename lives in the tree, not the blob. Perfect match for Freechains' payload model:

| Property | Git blob | Freechains payload |
|---|---|---|
| Content addressed | yes | yes |
| No filename stored | yes (filename lives in tree) | yes (no filename concept) |
| No metadata | yes (pure bytes) | yes (pure bytes) |
| Same content = same hash | yes | yes |
| Binary safe | yes | yes |
| Deduplicated automatically | yes (same content = same hash = stored once) | yes |

The blob is the one place in git's object model with a **perfect 1:1 match** to Freechains. Both are dumb content stores. The structured envelope around them (tree/commit in git, block in Freechains) is where identity, authorship, and DAG links live.
