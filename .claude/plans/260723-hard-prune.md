## Hard-Fork Checkpoint Pruning (Implicit, Structural Revoke)

Companion to `260721-revoke.md` / `260721-remove-blob.md`
(explicit, vote-driven revocation of one post) and
`done/260723-fork-7day.md` (the hard-fork rule itself).

## Goal

When `hardfork(oct,loc)` fires (`done/260723-fork-7day.md`),
the divergence with that remote is **permanent** — `meet()`
deliberately never learns rule 1, so no future `consensus()`
call will ever need to reconcile across that boundary again.
Everything strictly before the state checkpoint that forms
right after the hard-fork merge (`consensus.md:52-53`) becomes
**structurally dead** for consensus purposes on this peer.
This is *implicit* revocation: automatic, triggered by
`hardfork()` itself, not a community/author vote like
`260721-revoke.md`.

Question: can a peer discard (front-truncate) everything
before that checkpoint, the way `260721-remove-blob.md`
cooperatively discards one revoked payload — but for an
entire pre-fork slice at once?

## Flatten recipe (concrete)

Trigger: the 7-day / 100+ posts checkpoint is reached
(`done/260723-fork-7day.md`), flattening at the peer's own
current HEAD, before anything new is built on top locally.

```
git checkout --orphan tmp        # new root, keeps index + worktree
git add -A                       # capture full current tree (all blobs)
git commit ...                   # PINNED metadata -- see Blocker 2
git branch -D main
git branch -m main               # tmp -> main
git reflog expire --expire=now --all
git gc --prune=now               # reclaim now-unreachable old DAG
```

This is a squash-to-single-orphan-root: it **keeps the entire
current tree** (Track A — every payload blob retained with its
correct content hash) and drops only the commit DAG behind it.
The git is mechanically valid. The obstacles are all at the
Freechains layer, below.

## Blockers

Ordered by severity. Blocker 1 alone makes the recipe
unusable as written.

### Blocker 1 — chain identity (FATAL, `sync.lua:54-61`)

```lua
loc_root = git rev-list --max-parents=0 loc   -- root commit hash
rem_root = git rev-list --max-parents=0 rem
if loc_root ~= rem_root then ERROR("chain sync : incompatible genesis")
```

**Chain id = the root (genesis) commit hash.** Sync rejects any
peer whose root differs. Squashing mints a *new* root, so its
`--max-parents=0` hash ≠ every non-flattened peer's genesis →
`ERROR : chain sync : incompatible genesis`. The flattened peer
can no longer sync with anyone on the chain.

Fix — two alternatives:

| alt | approach | cost |
|-----|----------|------|
| **1a** (preferred) | match chains on **genesis content**, not root-commit hash — `add -A` already carries `.freechains/genesis.lua` + `random` forward into the flattened tree; sync compares that instead of `rev-list --max-parents=0` | changes the identity check in `sync.lua` |
| **1b** | accept flatten = a deliberate hard fork off the network: only *other* flatteners with a byte-identical deterministic root interoperate | network partitions into archive-tier vs flattened-tier |

This resolves the old "does sync need a flattened mode" open
question: **yes, mandatory.**

### Blocker 2 — deterministic root (mandatory for any interop)

Plain `git commit` stamps wall-clock date + local committer +
free-text message → a **non-deterministic** root. Two honest
peers who both flatten the same checkpoint then get different
root hashes → mutual "incompatible genesis" even between each
other. The commit must be pinned from checkpoint data:

| field | must be |
|-------------------------|------------------------------------|
| author+committer date   | the checkpoint commit's timestamp  |
| author+committer id     | a fixed constant                   |
| message                 | a fixed constant                   |
| parent                  | none                               |

The tree is already deterministic: git sorts tree entries, blob
hash = content, payload filenames sync identically across peers,
and `.freechains/state/*` is byte-identical by `state-hash.md`.
So a *pinned* commit over that tree yields an identical root on
every honest peer. Still open: nail the exact construction and
test peer-to-peer convergence.

### Blocker 3 — beg refs pin the old history

`refs/begs/beg-<hash>` point at commits whose parent chain **is**
the pre-squash mainline (`post.lua` parks them, then
`reset --hard HEAD~2`; `sync.lua` mirrors `+refs/begs/*`). After
squashing `main`, those refs still reach the whole old DAG, so
`gc --prune=now` **frees nothing**, and the begs dangle off a
history disconnected from the new root. Flatten must also
expire / re-anchor / drop `refs/begs/*`.

### Retrieval + metadata (the real feature work)

Squash destroys every pre-checkpoint commit, hence every
commit-hash post id. `get.lua`/`like.lua`/revoke resolve posts
through commit-level ops keyed by that id
(`merge-base --is-ancestor <hash>`, `trailer(<hash>)`,
`diff-tree <hash>`, `git show <hash>:<file>`), so all of them
break for old posts — even though the payload **bytes are still
in the tree** (see appendix). "Metadata must be complete" is
therefore not a footnote but the bulk of the work: fold the
commit-derived set — `blob` hash, `sign` (pubkey), `why`
(message), `time` — into `posts.lua`, and rework the resolvers
to read state + blob store instead of the commit. See
"Retrieval after truncation" below for the mechanism and its
limits.

### Signatures (trust model, with a caveat)

Treating the flattened root like genesis (unsigned, trusted —
`genesis.md`) is acceptable *as a trust model* and matches
Track B's "trust the checkpoint". Own the consequences:

- All per-post signatures are gone (the signed commits are
  gone). The peer can only *assert* authorship via trusted
  state, never *prove* it; full-history peers still can.
- Consensus / `pre-receive` must be confirmed to **accept** an
  unsigned root — tied to Blocker 1's flattened mode.

### Smaller checks

- **`add -A` scope** — OK-ish: `.freechains/tmp/*` is gitignored
  (skel `.gitignore`), so runtime scratch does not leak. But any
  *untracked-and-unignored* stray file gets absorbed → breaks
  determinism; `git clean` / verify first. (`layout.md` is stale:
  it says `now.lua` untracked; real path is `.freechains/tmp/`.)
- **Revoked payloads** — if a revoked/removed post's file is
  still on disk, `add -A` re-commits it → resurrects forgotten
  content. Confirm revoke / remove-blob `git rm`s the payload
  before trusting `add -A`.
- **Atomicity** — `branch -D main` before verifying `tmp` risks
  losing `main` on interrupt; build `tmp` → verify → swap.

## Two tracks, two risk profiles

### Track A — keep the whole tree (safe)

The recipe above is Track A: drop the DAG, keep every blob.
`.freechains/state/*.lua` is a pure cache — `apply()` replayed
over the post/like/revoke trailers reproduces it exactly (the
premise of `state-hash.md`'s exact-match check: trust comes from
*recomputing and comparing*, never from reading the file
blindly). A fresh peer can always fall back to a full replay
from genesis and rederive current state without any historical
snapshot; checkpoints (`consensus.md:60-98`) are an
optimization, not a trust dependency.

Cost: a future full-replay instead of a checkpoint-jump the next
time something walks back past the newest remaining checkpoint.
**Zero** verifiability lost. Modest storage reward — state files
are small; payloads are where the bloat is.

### Track B — also prune payloads (remove-blob's tradeoff)

Alternative to A, higher risk/reward. Payloads are signed
content, not a derived cache. Reclaiming their storage needs an
explicit `git rm` of the accumulated files at the graft — it is
**not** a free side-effect of orphaning (the files rode forward
into the tree; see appendix). Discarding them is exactly
`260721-remove-blob.md`'s cooperative, non-guaranteed forgetting,
wholesale: any peer holding the bytes can still re-serve them; a
NEW peer talking only to flatteners gets a checkpoint it must
**trust**, not rederive. Real storage win, real cost.

Track A and B are independent — a peer can do A without B.

### Retrieval after truncation: blob-hash in metadata

The mechanism behind the "Retrieval + metadata" blocker. Fold
the commit-derived fields into `posts.lua` so retrieval never
touches the old commit. Minimum is the payload's **blob hash**:

```
posts[a1] = { author=…, time=…, reps=…, blob = h }
```

Then `get --payload a1` becomes `git cat-file blob h` — blob `h`
is still reachable via the kept tree, no commit `a1` needed.
This is a **lighter decouple** than the full `sha256(payload)`
id (see Q below): the id stays the commit hash, so `likes/a1/…`,
`revokes/a1/…`, `posts[a1]` keep `a1` as their key — you only
stop *resolving* through the commit. For `get --metadata`, fold
`sign` / `why` / `time` in too.

Scope and limits:
- **keep-tree only.** Under Track B the `git rm` gc's the blob,
  so the stored blob hash **dangles**. Blob-hash helps A, not B.
- **content-only, trust-not-verify.** The SSH signature signs
  the *commit*, not the blob. Discarding the commit leaves the
  payload servable but no longer provably authored; blob-hash
  cannot recover the signature.

## Why orphan-at-tip, not interior rewrite

`prune.md`'s `--orphan` is the right primitive because of one
timing constraint: **flatten only at the current tip**. A git
commit hash is a Merkle chain — `parent` is inside the hash
(`git.md:62-77`). Editing an *interior* commit cascades new
hashes to every descendant: full history rewrite, rejected in
`260721-remove-blob.md` ("#1 rewrite: sacrifices the DAG").
Grafting a new root at the tip has no descendants yet to break;
only what's strictly before it is discarded, and no
already-published commit changes hash.

## Q: can post IDs survive a rewrite?

No, not in general — a hash-of-a-Merkle-chain fact, not an
engineering gap: `git.md:5-8` — **post ID = commit hash**, and
the hash includes `parent`. Any restructuring of the parent
graph changes the hash of every touched commit, i.e. the post's
own ID; every reference (`likes/<hash>`, `revokes/<hash>`) goes
stale and every remote copy disagrees.

Front-truncation does not hit that wall: it does not *preserve*
discarded IDs, it forgets them. Their effect is already folded
into the checkpoint's reps/revoke sums; nothing after the
checkpoint dereferences the original commit again.

Alternatives for keeping old posts individually addressable:

| alt | what | scope |
|-----|------|-------|
| **blob-hash value** (this plan) | keep id = commit hash, add `blob` as a value in `posts.lua`; survives front-*truncation* only | small, `posts.lua` + resolvers |
| **full decouple** | stable id `sha256(payload)` as a trailer, keyed everywhere ids are used; survives history *rewrite* too | large — most of the commit-mapping surface (`commands.md`), out of scope |

## Peer-compatibility consequence

Minting a new root is itself a divergence event between "did
flatten" and "did not flatten" peers — structurally a hard fork,
deliberately chosen. A flattened peer can only be cloned from
**filtered/partial** going forward
(`260721-remove-blob.md`'s `filter=blob:none` + by-hash payload
fetch), by peers willing to accept the checkpoint as trusted
(Track B) or redo a genesis replay to confirm it (Track A).
Mirrors remove-blob's "eager replication -> lazy fetch" shift
(`260721-remove-blob.md:247-259`): archive-tier and flattened-
tier peers coexist, same as full-payload holders vs not today.

## Open questions

- **Blocker 1 fix** — pick 1a (content-based identity) vs 1b
  (flatten = hard fork). 1a keeps flatteners on the network.
- **Blocker 2 construction** — pin the exact orphan-commit
  fields and test peer-to-peer convergence.
- **Blocker 3** — decide beg-ref fate: re-anchor pending begs
  onto the new root, or drop them.
- **Metadata fold** — eager vs lazy population of
  `sign`/`why`/`time` into `posts.lua`.
- **Automatic vs opt-in** — flatten the instant a peer
  hard-forks (max storage savings, archive tier shrinks) or
  manual (preserves the archive tier)?

Resolved:
- Sparse-checkout / bare-repo is **not** needed here (unlike
  remove-blob): orphan-at-tip has no interior-rewrite
  resurrection vector. Holds only while every `git add` stays
  targeted — grep confirms zero `git add -A` in the write path
  (the recipe's one-shot `add -A` is a deliberate flatten step,
  not a per-write add). Invariant: never add a blanket add to
  `post`/`like`/`sync`.
- Track A is worth it as its own tier (drop DAG, keep tree,
  serve old posts by id), not just cache pruning.

## Appendix: worked example (front-truncation vs in-place compaction)

Fake short hashes throughout.

### Starting chain

```
G (genesis)
 └─ a1 = commit(parent=G,    tree={post: "hello"})        -- POST, id = a1
     └─ b1 = commit(parent=a1, tree={like on a1, ...})     -- LIKE on a1, id = b1
         └─ c1 = commit(parent=b1, tree={state/*.lua})     -- "freechains: state" checkpoint,
                                                              right after hardfork() fires
```

Other files on disk name posts **by their commit hash**:

```
.freechains/likes/a1/KEY2      <- path embeds "a1"
.freechains/revokes/a1/KEY3
```

That's the concrete meaning of "post ID = commit hash"
(`git.md`): the hash `a1` isn't just an address, it's the
*name* other data structures point at.

### Front-truncation (this plan) — works

```
z1 = commit(parent=NONE, tree=c1's tree)   -- orphan root, grafted AT c1,
                                               nothing after it exists yet
      └─ (future posts build on z1 normally)
```

Commits `a1` and `b1` are **gone** — not renamed, not
preserved as commit objects, so nothing resolves them by their
commit-hash id anymore (that is what the blob-hash-in-metadata
section fixes for retrieval).

But their *tree content is not discarded by the orphan*.
Freechains chains are non-bare working trees and every write is
a `git add` of a tracked file, so git trees **accumulate**: the
post payload file and `.freechains/likes/a1/...` were committed
in `a1`/`b1` and then rode forward unchanged into `c1`'s tree.
Since `z1 = commit(tree=c1's tree)`, both files are **still
present in `z1`**. What the orphan drops is the *commit DAG*
(ancestry, and with it commit-hash addressability and the GPG
signatures), not the tip tree.

Consequence for Track B: actually reclaiming payload storage
needs an explicit `git rm` of the accumulated files at the
graft — it is **not** a free side-effect of orphaning. The
reps/revoke effect is independently summed into `z1`'s state
tables, so the raw files can go without losing derived state.

This all only works because truncation happens **at the current
tip**, before anything new points back at `a1`/`b1`.

### In-place compaction trying to *keep* `a1` addressable — breaks

Suppose instead you squash `G+a1` into one commit to shrink
history, but still want the post answerable at "a1" (so
existing `.freechains/likes/a1/KEY2` files elsewhere on the
network still resolve):

```
a1' = commit(parent=NONE, tree=a1's tree)   -- same payload bytes, different parent field
```

`parent` is inside the hash. Same tree, different parent ⇒
**different hash**. Call it `a1' = "x9f..."`, not `a1`. Every
`.freechains/likes/a1/...` file — on this peer and every peer
that already synced it — now names an object that doesn't
exist in the compacted repo. The like isn't "moved," it's
orphaned. No squash can reproduce the string `a1` again; that
would require breaking the hash function.

### The fix, if compaction-with-identity is ever wanted

Stop using the commit hash as the post's name. Add a stable id
inside the tree/trailer, e.g. `Freechains-post-id:
sha256(payload)`, and change `like.lua`/`revoke`/`sync.lua`/
`get.lua` to key off that trailer instead of `git rev-parse`.
Then `a1` can become `a1'` under any history rewrite and
`.freechains/likes/<post-id>/...` still resolves — but that's
the larger, decoupled-ID feature flagged above, not something
front-truncation needs.

## References

- `260721-revoke.md` — explicit, vote-driven Phase 1 revoke
- `260721-remove-blob.md` — cooperative blob removal, partial
  clone, the resurrection/bare-repo blockers, transfer model
- `done/260723-fork-7day.md` — hard-fork rule, `meet()` never
  learning rule 1 (why the boundary is permanent)
- `consensus.md` — checkpoint/replay pipeline this plan reuses
- `state-hash.md` — why trust comes from recompute-and-compare,
  not from reading state files
- `prune.md` — `--orphan` mechanics
- `git.md` — post ID = commit hash; Merkle-chain hash fields
