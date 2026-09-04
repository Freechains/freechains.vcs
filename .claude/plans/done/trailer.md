# Git Trailers in Freechains

## Background

### What Are Git Trailers

Structured key-value lines at the end of a commit message,
separated from the body by a blank line.
Formalized by `git interpret-trailers`. Format:

```
Short summary

Optional longer body paragraph.

Key: value
Key: value
```

Parsed with:

```bash
git log --format='%(trailers)'
git interpret-trailers --parse --only-trailers
```

No schema negotiation needed — any conforming tool can
consume them.

### Key Properties

1. **Machine-readable without schema negotiation** —
   `git interpret-trailers --parse` is standard.
2. **Human-readable in `git log`** — no special tooling to
   inspect.
3. **Survive most operations** — present in
   `git format-patch` output, email patches, `git log`.
4. **Composable** — multiple trailers of the same key are
   valid (e.g. multiple `Signed-off-by:`).
5. **Independent of Git's object model** — do not affect
   commit hash the way extra headers do.
6. **Fragile under rebase** — body text is rewritten
   verbatim, but a rebase that edits the message loses
   trailers unless explicitly preserved. Main limitation
   vs. extra commit headers.

### Real-World Uses

#### Authorship & Attribution

| Trailer          | Use                                         |
|------------------|---------------------------------------------|
| `Signed-off-by:` | Linux kernel DCO — certifies right to submit|
| `Co-authored-by:`| GitHub shows multiple avatars on the commit  |
| `Reported-by:`   | Credits bug reporter                        |
| `Reviewed-by:`   | Tracks review chain (kernel, QEMU)          |
| `Tested-by:`     | Records who validated the patch             |
| `Acked-by:`      | Maintainer acknowledgement without review   |
| `Cc:`            | Used in `git send-email` to CC maintainers  |

#### Issue Tracking Integration

| Trailer        | Use                                          |
|----------------|----------------------------------------------|
| `Fixes: #123`  | GitHub/GitLab close the issue on merge       |
| `Closes: #123` | Same effect, different convention            |
| `Refs: #123`   | Links without closing                        |
| `Bug: <url>`   | Debian packaging links to bug tracker        |

#### Referencing Past Commits

| Trailer                   | Use                               |
|---------------------------|-----------------------------------|
| `Fixes: <sha> ("subject")`| Linux kernel — SHA + quoted subject, validated by `checkpatch.pl` |
| `Reverts: <sha>`          | Documents which commit is undone (`git revert -x`)                |
| `cherry-picked-from: <sha>`| Inserted by `git cherry-pick -x`, records origin                 |
| `Backport-of: <sha>`      | Linux stable / Mesa for stable branches                          |
| `Depends-on: <sha>`       | Gerrit — ordering dependency between patches                     |
| `Link: <lore url>`        | Kernel — stable reference to mailing list thread                 |

#### Change Management & CI

| Trailer            | Use                                    |
|--------------------|----------------------------------------|
| `Change-Id:`       | Gerrit — stable ID across amended commits |
| `skip-ci:`         | GitLab CI / GitHub Actions suppress runs  |
| `BREAKING-CHANGE:` | Conventional Commits — triggers major bump|

#### Security & Compliance

| Trailer | Use                                            |
|---------|------------------------------------------------|
| `CVE:`  | Tags commits addressing specific vulnerabilities|

### Linux Kernel `Fixes:` Format

Richest real-world example:

```
commit 9f8d03a7b1c2
Author: Someone <someone@kernel.org>

    net: fix null deref in packet handler

    The handler did not check for NULL before
    dereferencing the skb pointer in the error path
    introduced by the previous change.

    Fixes: 1da177e4c3f4 ("net: add packet handler")
    Signed-off-by: Someone <someone@kernel.org>
```

- SHA + quoted subject = human-readable without `git log`
- `checkpatch.pl` validates the format
- `b4` and `get_maintainer.pl` parse it for patch series
- Allows automated tracing of bug introductions

### Radicle's Approach

Radicle uses a `rad:` trailer namespace to embed patch
metadata and identity information into commit messages —
part of its COBs (Collaborative Objects) layer.
Unlike Freechains' approach of embedding signatures in
commit object headers, Radicle keeps signing at the refs
level (sigrefs) and uses trailers for higher-level metadata.

---

## Current Usage

One trailer: `freechains: <kind>` where kind is `post` or
`like`.

```
git commit --trailer 'freechains: post' ...
git commit --trailer 'freechains: like'  ...
```

Used in `src/freechains:330` for every chain commit.

## Plan

### 1. Rename `freechains:` to `Freechains-Kind:`

- Conventional trailer capitalization
- Values: `post`, `like`

```
--trailer 'Freechains-Kind: post'
--trailer 'Freechains-Kind: like'
```

### 2. Add `Freechains-Ref: <commit-hash>`

- Explicit back-reference to the target post
- Added on like/dislike commits (and future quote/reply)
- Redundant with `.freechains/likes/*.lua` payload, which is
  the canonical source via `dofile()`
- Useful for quick `git log` queries without loading lua

```
--trailer 'Freechains-Kind: like'
--trailer 'Freechains-Ref: abc123def456'
```

### 3. Add `Freechains-Peer: <pubkey>` on merge commits

- Peers sign merge commits and identify themselves
- Merge commits already exist at sync time (`--no-ff`
  required, see [merge.md](merge.md) §3)
- The git author field already records the committer, but
  `Freechains-Peer:` records the peer's **chain-level
  public key** — the identity that matters for reputation

```
--trailer 'Freechains-Peer: CA6391CE...'
```

- Combined with SSH signing (`git commit -S`), this
  creates a signed attestation: "peer X saw this branch
  state at time T"

#### Peer reputation

- Each signed merge is a verifiable act of service:
  the peer fetched, validated consensus, and committed
- Peers that consistently relay content build a track
  record in the DAG — countable via
  `git log --grep='Freechains-Peer: <key>'`
- A peer's merge count is a measure of participation
  and reliability, independent of authoring content
- Enables trust decisions: prefer syncing with peers
  that have a long, visible history of honest merges
- Unlike author reputation (which flows from likes),
  peer reputation is earned by doing work that is
  costly to fake — you must actually fetch and validate

---

## Future Trailer Ideas

### `Freechains-Parent: <sha>`

Encodes DAG edges *inside* the commit message, independent
of Git's own parent pointers.
Allows reconstruction of the Freechains DAG even if Git
history is later flattened or rebased — useful for archiving
or interop scenarios.

Contrast with Git's native parent pointers: those are baked
into the commit object and affect the hash.
Trailers are message-layer only — cheaper to add but easier
to lose.

### `Freechains-Chain: <chain-id>`

Tags a commit as belonging to a specific chain.
Enables filtering across a multi-chain repository or audit
log without parsing the full object.

### `Freechains-Sig: <base64-ed25519-signature>`

Simpler than embedding signatures as extra commit object
headers (which requires custom Git tooling to insert).
Trailers can be added by any script via
`git interpret-trailers --trailer`.
Trade-off: signatures in trailers do not cover the commit
hash deterministically the way extra headers do; the
signature must explicitly commit to the SHA it is signing.

### `Freechains-Reputation: <score>`

Snapshot of like/dislike balance at the time of observation —
useful for forensics and auditing even if the live SQLite
cache is lost.

---

## Trailers vs Extra Commit Headers

| Aspect              | Trailers                      | Extra Headers            |
|---------------------|-------------------------------|--------------------------|
| Tooling required    | None — standard `interpret-trailers` | Custom Git build or patch|
| Visibility          | `git log` — human readable    | Hidden from standard log |
| Affects commit hash | No                            | Yes                      |
| Survives rebase     | Only if message is preserved  | N/A — hash changes       |
| Signature coverage  | Must explicitly bind to SHA   | Can cover full object    |
| Composability       | Multiple same-key allowed     | Depends on implementation|

For Freechains, **extra headers are preferable for
signatures** (integrity guarantee) and **trailers are
preferable for metadata** (chain membership, DAG parents,
reputation snapshots) because metadata legibility and
tooling compatibility outweigh the need for cryptographic
coverage at the message layer.

---

## Parsing Snippets

```bash
# Extract all trailers from a commit
git log -1 --format='%(trailers)' <sha>

# Parse specific key
git interpret-trailers --parse --only-trailers \
  --trim-empty \
  < <(git log -1 --format='%B' <sha>) \
  | grep '^Freechains-Parent:'

# Add a trailer programmatically
git interpret-trailers \
  --trailer 'Freechains-Chain: pubchat' \
  --in-place .git/COMMIT_EDITMSG
```

---

## Notes

- Finding the lua file in a commit is trivial:
  `git diff-tree --no-commit-id --name-only -r <hash>`
  returns the single changed file, then `dofile()` it.
- Parsing `.lua` payloads is preferred over parsing trailers,
  since we already have a lua interpreter.
- Trailers are part of the commit message, so they replicate
  and sign automatically.
- Multiple `--trailer` flags combine in a single `git commit`.

## Status

- [ ] Rename `freechains:` → `Freechains-Kind:`
- [ ] Add `Freechains-Ref:` to like/dislike commits
- [ ] Add `Freechains-Peer:` to merge commits
