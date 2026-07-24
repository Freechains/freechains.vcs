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

## Two tracks, two risk profiles

### Track A — prune old STATE commits only (safe)

`.freechains/state/*.lua` is a pure cache: `apply()` replayed
over the post/like/revoke commit trailers reproduces it
exactly (that is the whole premise of `state-hash.md`'s
exact-match check — trust comes from *recomputing and
comparing*, never from reading the file blindly).

Consequence: a fresh peer can always fall back to a full
replay from genesis over the raw commit DAG and rederive
current state **without consulting any historical state
snapshot**. Checkpoints (`consensus.md:60-98`) exist purely
so *normal* merges don't pay that genesis-to-tip replay cost
every time — they are an optimization, not a trust
dependency.

So: dropping old state-commit tree content costs a future
full-replay (instead of checkpoint-jump) the next time
something needs to walk further back than the newest
remaining checkpoint. It costs **zero** verifiability. Low
risk, modest reward (state files are small; payloads are
where the real bloat is).

### Track B — prune PAYLOADS too (remove-blob's tradeoff, wholesale)

Payloads are the actual signed content — not a derived
cache. Discarding them before a checkpoint is exactly
`260721-remove-blob.md`'s cooperative, non-guaranteed
forgetting, just applied to an entire pre-fork slice instead
of one revoked post. Same non-goal applies: any peer who
already holds the bytes can still prove and re-serve them;
a NEW peer who only talks to peers that flattened gets a
checkpoint they must **trust**, not one they can independently
rederive. This is the real storage win, and the real cost.

Track A and B are independent — a peer can do A without B.

## Mechanism: orphan-at-checkpoint, not history rewrite

`prune.md`'s `--orphan` technique is the right primitive, with
one timing constraint: **flatten only at the peer's own
current HEAD**, immediately after the hard-fork-resolving
state commit lands, before anything new is built on top of it
locally.

Why the timing matters: a git commit hash is a Merkle chain —
`parent` is inside the hash (`git.md:62-77`). Editing an
*interior* commit (stripping old state/payload content) changes
its hash, which cascades forward and changes every descendant's
hash too. That is full history rewrite, already rejected in
`260721-remove-blob.md` ("#1 rewrite: sacrifices the DAG").

Grafting a **new root** exactly at the current tip sidesteps
this: there are no descendants yet to break. Nothing after the
checkpoint is touched; only what's strictly before it is
discarded. Future local commits build on the new orphan hash
going forward — no already-published commit changes hash.

### Determinism requirement

If two honest peers independently hard-fork against the same
rejected remote, they compute byte-identical derived state
(that's what makes the FF exact-match check meaningful at all).
For their independently-minted orphan roots to also match, the
orphan commit's hash-relevant fields must be **derived from the
checkpoint's own data**, not wall-clock "now" — e.g. reuse the
original checkpoint commit's author/committer timestamp, not
the flatten time. Otherwise two honest peers who both flattened
produce different roots and can no longer FF against each other
even though nothing substantive diverged. This needs to be
nailed down precisely, not just a "same-ish" approximation.

## Q: can post IDs survive a rewrite?

No, not in general, and this is a hash-of-a-Merkle-chain fact,
not an engineering gap: `git.md:5-8` — **post ID = commit
hash**, and the hash includes `parent` (`git.md:62-77`). Any
restructuring of the parent graph (squash, compact, reparent)
changes the hash of every touched commit, i.e. changes the
post's own ID. Every existing reference to that ID elsewhere in
the DAG — `.freechains/likes/<hash>`, `.freechains/revokes/
<hash>` (`260721-revoke.md`) — goes stale, and every remote
peer's copy disagrees with the rewriter's.

Front-truncation (this plan) does not hit that wall, because it
does not try to *preserve* the discarded IDs — it forgets them
outright. Their effect is already folded into the checkpoint's
derived reps/revoke sums; nothing after the checkpoint needs to
dereference the original commit object again.

**General, identity-preserving rewrite** (squash history but
keep old posts individually addressable/likeable) is a
different, larger feature: it requires decoupling "post ID"
from "commit hash" entirely — e.g. a content hash of the
payload+signature carried as an explicit trailer, used as the
key everywhere IDs are used today (`like.lua`, revoke,
`sync.lua` trailers, `get.lua`). That touches most of the
commit-mapping surface (`commands.md`) and is out of scope
here; noted as a prerequisite if compaction-with-identity is
ever wanted instead of forgetting.

## Peer-compatibility consequence

Minting a new root is itself a divergence event between "did
flatten" and "did not flatten" peers — structurally the same
shape as a hard fork, just deliberately chosen instead of
adversarial. A peer that flattens can only be cloned from
**filtered/partial** going forward (`260721-remove-blob.md`'s
already-proven `filter=blob:none` + by-hash payload fetch), and
only by peers willing to accept the checkpoint as trusted
(Track B) or willing to redo a genesis replay to confirm it
(Track A, still possible since nothing was discarded that
verification depends on... except the discarded objects
themselves, which is the point). This mirrors remove-blob's
"eager replication -> lazy fetch" shift
(`260721-remove-blob.md:247-259`): full-history archive peers
and flattened peers become two coexisting tiers, same as
full-payload holders vs not today.

## Open questions

- Pin down the deterministic-orphan-hash construction (see
  above) precisely enough to test peer-to-peer convergence.
- Track A alone: is checkpoint-cache pruning worth a dedicated
  feature given state files are small, or should it just be a
  side effect of Track B when a peer opts in?
- Does `sync.lua`'s existing FF/state-hash check
  (`state-hash.md`) need a new "peer is flattened, don't expect
  full ancestry" mode, or does it already degrade gracefully
  (shallow history) the same way partial clone does in
  `260721-remove-blob.md`'s tests?
- Bare-repo / sparse-checkout prerequisite from
  `260721-remove-blob.md` (non-bare chains resurrect removed
  blobs via `git add`) applies here too for Track B.
- Should flattening be automatic (every peer does it the
  instant it locally hard-forks) or opt-in/manual? Automatic
  maximizes storage savings but means the "full archive" tier
  shrinks over time as fewer peers retain deep history.

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

`a1` and `b1` are simply **gone** — not renamed, not
preserved. Their *effect* survives because it's already summed
into `z1`'s tree (reps total, revoke sums). Nothing downstream
ever needed to say "a1" again — `z1` is a fresh root, and
`.freechains/likes/a1/...` was inside `b1`'s tree, discarded
along with it. No dangling reference, because nothing after
`z1` was ever created yet to hold one.

This only works because truncation happens **at the current
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
