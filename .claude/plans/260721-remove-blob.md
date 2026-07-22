# Remove Blob: Cooperative Payload Revocation

Phase 2 of revocation.
Companion to `260721-revoke.md` (Phase 1 = display-level hide).

Goal: let honest peers **physically drop** a REVOKED post's
payload bytes and **stop serving** them, while keeping the
consensus DAG intact.

This is *cooperative* forgetting, not guaranteed erasure —
see the non-goal below.

See also: `prune.md` (history flatten), `reps.md:243`
(revocation rule), `sync.lua:10,23` (transport).

## NON-GOAL: guaranteed network-wide forgetting (impossible)

Freechains is a signed, content-addressed, fully-replicated
DAG. That is exactly what makes global erasure impossible:

```
signed post ──▶ synced to peers before revocation
   ├─ each holds the bytes → cannot be compelled to delete
   ├─ signature + hash stay in the DAG → any holder can PROVE
   │                                     the bytes are authentic
   └─ one non-cooperative peer re-serves → back in the network
```

So `reps.md:250` "not retransmitted" and `README.md:429`
"right to be forgotten" are NOT achievable as guarantees.
What IS achievable:

- honest peers respecting REVOKED drop + stop serving payload;
- a new peer talking only to honest peers never receives it;
- content survives among pre-revocation holders and any peer
  that chooses to retain it.

That cooperative ceiling is the same one GDPR-style forgetting
hits everywhere. Design to it; do not over-promise.

## The core tension (why removal is delicate)

Git is append-only + content-addressed.
A commit tree references a blob by hash; the hash *is* the
content.

```
rewrite tree to drop payload: new hashes -> DAG broken -> peers DISAGREE
rm blob in place:             same hashes -> DAG intact -> peers AGREE  ✓
```

`rm blob` is the only route that preserves consensus.
The hard part is then serving new peers without that blob.

## Can we disable git packaging?

**On disk: yes** (keep blobs loose so one is `rm`-able):

```
git config gc.auto            0
git config gc.autoPackLimit   0
git config fetch.unpackLimit    <huge>
git config receive.unpackLimit  <huge>
git config transfer.unpackLimit <huge>
```

**On the wire: no.** The smart protocol *is* a packfile; a
served fetch runs `pack-objects` on the fly over the full
object closure. `unpackLimit` only controls receiver storage.

Loose-object config makes `rm` clean but does NOT fix serving.

## The serving wall

Freechains sync = vanilla `git push` / `git fetch`.
Vanilla transfer demands the complete object closure of every
reachable commit:

```
new peer: git fetch ──▶ upload-pack ──▶ pack-objects
                                        └─ blob <h> MISSING -> ERROR
```

One removed blob -> chain unservable to newcomers.
No "skip one object" exists in the wire protocol.

## Consensus does not need payloads

Validation uses signatures + state files, not payload content
(`sync.lua consensus()` reads pubkeys; reps come from
`state/*.lua`). So a peer can validate ordering and reps
without any payloads — this is what makes filtered transfer
viable.

## Options to serve a new peer with the blob gone

| # | Approach | Serves peer? | Cost |
|---|-----------------------------------|---------|--------------------------|
| 1 | Rewrite (filter-repo / `--orphan`) to tombstone | yes | hashes change -> DAG/consensus broken |
| 2 | `git replace` -> placeholder | reads only | packer ignores replacements; no serving fix |
| 3 | **Partial clone (`filter=blob:none`, promisor)** | yes | sync change only; payloads stay in tree |
| 4 | Sidecar payloads (content outside the tree) | yes | storage + signing rewrite |

## Chosen direction: partial clone (#3)

Primary because it serves peers with a removed blob **without**
changing hashes, storage, or signing:

- Served pack is commits + trees only (`filter=blob:none`), so
  a `rm`'d blob is never read -> serve succeeds.
- Client lazily fetches the payloads it wants from a promisor;
  a REVOKED payload has no provider -> peer permanently lacks
  it (a harmless promisor gap, not fsck corruption).
- Payloads stay in the tree; signing model unchanged.

Steps:

- enable `uploadpack.allowFilter` on serving side;
- switch `sync.lua` fetch to a filtered/partial fetch;
- reader (`get.lua`) tolerates an absent payload -> tombstone;
- honest node `rm`s the revoked loose blob (loose-object config
  above) and stops offering it.

### Alternative: sidecar (#4)

Store payloads outside the committed tree, keyed by post hash,
integrity via `sha256(payload)` in signed metadata. Cleaner
separation but a heavier storage + signing change
(`signing.md`, `git.md`). Keep as fallback if partial-clone
transport proves impractical.

### Rejected

- #1 rewrite: sacrifices the DAG (the whole point).
- #2 `git replace`: does not fix serving.

## Feasibility — TESTED 2026-07-21 (fetch side)

Built a 3-post repo, `rm`'d one payload's loose blob, measured
every path:

| Test                                       | Result |
|--------------------------------------------|--------|
| local `git log` / DAG / hashes             | OK, intact |
| read OTHER posts (`git show <c>:file`)     | OK |
| read the REMOVED post                      | graceful "could not fetch" (not corruption) |
| **full** clone (vanilla) from the node     | **ABORTS** — `pack-objects died, unable to read <blob>` |
| **partial** clone `--filter=blob:none --no-checkout` | **OK — exit 0, full DAG, fsck clean** |
| read good posts in partial clone           | OK (lazy fetch on demand) |
| read removed post in partial clone         | graceful error |
| incremental `git fetch` from the node      | OK — got new commit |

Conclusions:

- Vanilla full clone needs the whole object closure -> one
  removed blob makes the chain unservable to newcomers.
- `--filter=blob:none` builds a pack of commits+trees only, so
  the removed blob is never read -> serve succeeds.
- `--no-checkout` matters: plain `git clone --filter` fails at
  the final working-tree checkout (hydrates every file);
  Freechains never checks out (`get.lua` = `git show
  <hash>:file`), so no-checkout is exit 0 and fsck clean.
- Incremental fetch was never at risk: it transfers only the
  delta above the common ancestor, and a removed blob sits
  below the cut in shared history, so it is never renegotiated.

Net: cooperative removal that "keeps git working" is REAL, with
**no storage or signing change** — partial fetch + loose-blob
config + tombstone-aware `get.lua`.

## Open questions

- **NEXT TEST (push side):** Freechains syncs via `git push` to
  a receiver hook (`sync.lua:10`), not fetch. Only the
  fetch/clone side is proven. Test: can a node whose blob is
  removed still `git push` its refs to a receiver, and can a
  receiver accept a push that omits a filtered blob? Does
  `push --filter` / partial-push exist, or must sync flip to
  fetch-pull for chains with removed payloads?
- Promisor identity: which peer(s) act as promisor for
  non-revoked payloads?
- Wire representation of a tombstone (absent vs explicit
  marker) so peers distinguish "revoked" from "not yet synced".
- Back-compat: existing chains embed payloads in the tree and
  transfer full closure — migration/opt-in path.

## Progress

- [x] Fetch/clone side feasible (tested 2026-07-21, see above)
- [ ] **NEXT: push-side test** (blob-removed node push +
      receiver accepting filtered push)
- [ ] Loose-object git config
- [ ] `uploadpack.allowFilter` + filtered fetch in `sync.lua`
- [ ] `get.lua` tolerates absent payload -> tombstone
- [ ] `rm` revoked loose blob on honest nodes
- [ ] Doc: cooperative-only guarantee (no global erasure)
- [ ] Migration for full-closure chains

## Cross-references

- `260721-revoke.md` — Phase 1 (display-level revocation);
  this plan is its Phase 2.
- `prune.md` — `--orphan` flatten (rejected rewrite option).
- `reps.md:243,250` — revocation rule; "not retransmitted"
  downgraded here to cooperative.
- `signing.md`, `git.md` — relevant to the sidecar alternative.
- `sync.lua:10,23` — vanilla git push/fetch transport.
