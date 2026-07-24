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

Flatten by **shallow graft** at a retention-boundary checkpoint
`c1` — the newest state checkpoint older than `T_keep` (see
"Two periods" below), **not** the 7-day hardfork checkpoint.
Keep `c1` and every descendant at their **real, network-shared
hashes**; drop only the ancestors below `c1`.

```
git rev-parse <c1> > .git/shallow    # treat c1 as parentless (graft)
git reflog expire --expire=now --all
git gc --prune=now                   # prunes everything below c1
```

Why shallow, not `--orphan`: `c1` is the checkpoint that forms
right after the rule-1 merge, and it is **shared by propagation**
— one peer bakes it, the rest fetch that same object via
`sync`'s `+main` (`done/260723-fork-7day.md`). Its hash is the
common commit the whole side of the fork already agrees on, and
the one `sync` feeds to merge-base to compute the fork point.
`--orphan` would throw that shared hash away and mint a local
one → guaranteed divergence (see rejected alt below). Shallow
keeps `c1`'s real hash and merely forgets its ancestors.

This retains the entire current tree (Track A — every payload
blob still reachable via `c1`'s tree). The git is mechanically
valid. The obstacles are all at the Freechains layer, below.

## Two periods: consensus vs retention

The 7-day hardfork threshold and the prune boundary answer
**different** questions and should be **separate knobs**:

| period | value | governs | concern |
|--------|-------|---------|---------|
| `T_fork` | 7 days **or** 100 posts | consensus: local activity freezes ordering (rule 1, `done/260723-fork-7day.md`) | ordering / attacker |
| `T_keep` | 30 days **or** 500 posts | retention: how much ancestry to keep before grafting | storage / sync |

Both live in `constants.lua` next to the existing
`fork = { time, posts }`; add `keep = { time = 30*24*h, posts = 500 }`.

**Opposite polarity** — each is conservative for what it guards:

- `T_fork` fires **early**: `crossed = days≥7 or posts≥100`.
- `T_keep` prunes **late**: keep if `days<30 or posts<500`, i.e.
  prune only what is beyond **both**. A fast chain keeps 30 days
  (≫ 500 posts); a slow chain keeps until 500 posts accumulate
  (tiny history, cheap to hold).

The graft boundary `c1` trails `T_keep`, not `T_fork`. Peers
offline past `T_keep` fork below `c1` and are **rejected**
(Blocker 3 — a pruned node cannot verify below its boundary);
they recover by re-anchoring. Invariant:
`T_keep ≥ straggler_tolerance > T_fork` — pruning trails
consensus by a safety margin.

## Blockers

Ordered by severity. Blocker 1 alone makes the recipe
unusable as written.

### Blocker 1 — the genesis-identity guard (`sync.lua:54-61`)

```lua
loc_root = git rev-list --max-parents=0 loc   -- traversal root
rem_root = git rev-list --max-parents=0 rem
if loc_root ~= rem_root then ERROR("chain sync : incompatible genesis")
```

Shallow graft **preserves** the shared checkpoint hash `c1`, so
merge-base with peers still resolves on `c1` — this works even
between a shallow peer and a full-history peer, since both hold
`c1`. Identity as a whole is fine. The one residual: on a shallow
repo `rev-list --max-parents=0` returns the **shallow boundary
`c1`**, not the true genesis `G`. So a flattened peer reports
root `c1` while a full peer reports `G` → this specific guard
still trips `incompatible genesis`.

Fix — compare on the true genesis hash, which is **already known
out-of-band**: the chain dir is named `#<genesis-hash>`
(`chains.lua` — `hash = "#" .. rev-parse HEAD` of the genesis
commit). So the guard can compare that chain id, independent of
shallow depth, with **no new field to carry**. Merge-base
already works, so this is a narrow guard change, not a redesign.
Resolves the old "does sync need a flattened mode" question:
**yes, but minimal.**

### (removed) deterministic-root blocker

The earlier `--orphan` design minted a new root and so needed
its commit fields pinned for two honest flatteners to converge.
Shallow graft **mints nothing** — `c1`'s hash comes from
propagation, exactly like normal sync — so this blocker is gone.
Any determinism concern about `c1` itself is pre-existing in the
consensus/merge layer, not introduced by pruning.

### Blocker 2 — beg refs pin the old history

`refs/begs/beg-<hash>` point at commits whose parent chain **is**
the pre-checkpoint mainline (`post.lua` parks them, then
`reset --hard HEAD~2`; `sync.lua` mirrors `+refs/begs/*`). A beg
ref is a gc root, so it keeps the whole old DAG below `c1`
reachable — `gc --prune=now` then **frees nothing**, defeating
the shallow graft.

Resolved: **drop sub-boundary begs.** `sync.lua:499` already has
stale-beg cleanup (drops begs whose post is already in main);
flatten extends it — begs parked below `c1` are unaccepted *and*
past `T_keep`, so drop them the same way. No re-anchor needed
(re-anchoring would change their hashes anyway).

### Retrieval + metadata (the real feature work)

The shallow graft prunes every pre-checkpoint commit, hence
every commit-hash post id below `c1`.
`get.lua`/`like.lua`/revoke resolve posts
through commit-level ops keyed by that id
(`merge-base --is-ancestor <hash>`, `trailer(<hash>)`,
`diff-tree <hash>`, `git show <hash>:<file>`), so all of them
break for old posts — even though the payload **bytes are still
in the tree** (see appendix). The fold is **smaller than it
looks**: `posts.lua` already stores `author` (= the `sign`
pubkey), `time`, `reps`, `revoke` (`common.lua:193`). Only
**`blob`** (payload location) and **`why`** (message) are
missing, plus **`backs`** (currently a DAG walk that breaks
below `c1`). Add those to `posts.lua` and rework the resolvers
to read state + blob store instead of the commit.

The fold **must be eager** — populated *before* the graft, while
the commits still exist. Lazy population is impossible: the
prune destroys the very commit the fields would be read from.
See "Retrieval after truncation" below for the mechanism and its
limits.

### Blocker 3 — sub-boundary straggler merge (and its DoS)

A peer P offline longer than `T_keep` forks at `oct`, now **below**
`c1`. `merge-base(our_tip, P_tip) = oct`, which we pruned, and
consensus rule 2 needs the `G..oct` prefix reps — also pruned. So
the merge cannot compute as-is.

**Decision: reject sub-boundary forks.** A pruned node *cannot*
verify anything below its boundary — and this is the key point,
not a limitation to engineer around. To validate P's fork at
`oct`, the node needs `oct`'s reps state; deriving it means
replaying `genesis..oct`, which the node **pruned**. So it would
have to re-fetch and replay the *entire* prefix — which is
exactly the DoS below. There is no cheap trustless deepen:

| | |
|---|---|
| trigger | any peer advertises a branch forking below `c1` |
| to verify it | re-fetch `genesis..oct` + full replay (un-prune) |
| attacker cost | ~nil — one advertisement pointing at *real* old history |
| amplification | fork from genesis for maximal replay; repeat from sock-puppets |

The prefix is signed by others so it can't be *fabricated* (this
is resource exhaustion, not a consensus attack), and you can't
pre-filter by merit (the merit-reps live in the pruned prefix).
So the only coherent options are **reject** or **trust blindly**
— and trust-blindly is unacceptable. Therefore:

- **`pre-receive` / `sync recv` rejects any inbound branch
  forking below the local boundary.** No deepen path exists to
  DoS.
- **Blacklist** peers that repeatedly advertise deep forks.
- **Straggler recovery = re-anchor.** A peer offline past
  `T_keep` re-posts its still-wanted content as *new* posts on
  the current tip (new ids, pays current reps). Its old
  DAG-position and pre-boundary reps are gone — consistent with
  the boundary being permanent.

Note this **corrects an earlier draft** that claimed deepen was
a cheap "verify, not trust" recovery. It is not: verify requires
the pruned prefix, so deepen ≡ un-prune ≡ the DoS. `T_keep`
(Two periods) still helps: sub-boundary forks only arise for
peers offline longer than 30 days / 500 posts.

### Signatures (trust model, with a caveat)

The kept checkpoint `c1` keeps its real hash, but the **signed
post commits below it are pruned**. Their per-post signatures go
with them; the peer can only *assert* pre-checkpoint authorship
via trusted state, never *prove* it (full-history peers still
can). That matches Track B's "trust the checkpoint". `c1` itself
stays whatever it was — signed or not — so no unsigned-root
question arises (unlike the old orphan design).

### Smaller checks

- **Revoked payloads** — verified: **no `git rm` exists anywhere
  in `src/`**, so revoke (`common.lua`, a negative like) never
  removes the payload file; it survives in `c1`'s tree
  regardless. Forgetting a revoked payload is unimplemented and
  belongs to `260721-remove-blob.md`, not this plan. Out of
  scope here.
- **`.git/shallow` is low-level** — writing it by hand then
  `gc --prune=now` is the local-repo path to shallowness; verify
  (test) git honors the graft for prune and that no other ref
  (tag, reflog, beg) keeps ancestors alive.

## Two tracks, two risk profiles

### Track A — keep the whole tree (safe)

The recipe above is Track A: drop the ancestry below `c1`, keep
`c1`'s tree (every blob) intact.
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
explicit `git rm` on `c1`'s tree — it is **not** a free
side-effect of the shallow graft, which only drops ancestor
objects and never touches the kept tree (the payload files rode
forward into `c1`; see appendix). Discarding them is exactly
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

## Mechanism: shallow graft vs orphan vs interior rewrite

Three ways to shed pre-checkpoint history; only shallow keeps
the shared hash.

| approach | `c1` hash | verdict |
|----------|-----------|---------|
| **interior rewrite** (strip old commits in place) | changes (Merkle cascade — `parent` is in the hash, `git.md:62-77`) | rejected in `260721-remove-blob.md` ("#1 rewrite: sacrifices the DAG") |
| **`--orphan`** (mint new parentless root at the tip) | changes (new root) | **rejected here** — destroys the checkpoint hash the network shares by propagation; merge-base with peers breaks |
| **shallow graft** (`.git/shallow` = `c1`, gc ancestors) | **unchanged** | chosen — `c1` keeps its real hash; only ancestors are forgotten |

Shallow is strictly better than orphan for this case: the
checkpoint is not a fresh boundary we get to invent, it is an
already-agreed commit, so the goal is to *keep* its hash while
forgetting what's below — exactly what a shallow graft does.

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

Because shallow keeps `c1`'s real hash, a flattened peer is
**not** a fork of the network — it agrees on `c1` and every
descendant, it just cannot serve or verify history below `c1`.
With rolling-auto flattening every peer converges to the same
shallow tier, so a newcomer clones from `c1` forward and
**trusts** the checkpoint state (Track B, network-wide) rather
than replaying from genesis. Nothing below any peer's boundary
is verifiable anymore — that is the accepted cost of pruning
everywhere, and the reason sub-boundary forks are rejected
(Blocker 3) rather than reconciled.

## Open questions

All policy decisions are made (below). Remaining is a single
test, not a decision: confirm `git gc` honors a hand-written
`.git/shallow` for prune, with no other ref keeping ancestors
alive.

Resolved:
- **Trigger = rolling auto** — every peer shallow-flattens on a
  rolling `T_keep` schedule. Consistent with Blocker 3
  reject-only: no node depends on another retaining deep
  history, so auto-flatten everywhere is safe. Cost accepted:
  newcomers trust the checkpoint (Track B network-wide);
  >`T_keep` stragglers re-anchor.
- **`T_keep` = 30 days or 500 posts** — in `constants.lua` as
  `keep = { time, posts }`; keep-if-recent-by-either polarity
  (dual of `T_fork`'s or-trigger).
- **Blocker 3 = reject sub-boundary forks** — a pruned node
  cannot verify below its boundary (verify ⇒ un-prune ⇒ DoS);
  reject + blacklist repeat offenders; stragglers re-anchor.
- **Shallow graft, not `--orphan`** — keep `c1`'s real,
  network-shared hash; only forget ancestors. Dissolves the
  minted-root identity break and its determinism requirement.
- **Blocker 1 guard = 1a, ~free** — compare on the genesis hash,
  already known as the chain dir name `#<genesis-hash>`
  (`chains.lua`); no new field.
- **Blocker 2 begs = drop** — sub-boundary begs are unaccepted
  and past `T_keep`; extend the existing `sync.lua:499` stale-beg
  cleanup.
- **Metadata fold = eager, small** — only `blob`/`why`/`backs`
  missing (`author`/`time`/`reps` already in `posts.lua`); lazy
  is impossible (prune destroys the source).
- **Revoked-payload removal = out of scope** — no `git rm` in
  `src/`; belongs to `260721-remove-blob.md`.
- Sparse-checkout / bare-repo is **not** needed: shallow never
  rewrites interior history or rebuilds the tree, so the
  remove-blob `add -A` resurrection vector never arises here.
  (Invariant still worth keeping: no blanket `git add` in
  `post`/`like`/`sync`.)
- Track A is worth it as its own tier (drop ancestry, keep
  tree, serve old posts by id), not just cache pruning.

## Implementation order

Dependency-ordered. The metadata fold (step 2) must ship and be
populating **before** any prune runs (steps 3+), or pruned posts
become unresolvable; reject (step 5) must precede rolling-auto
(step 6) so no prune opens a deepen-DoS window.

| # | step | file / place | notes |
|---|------|--------------|-------|
| 1 | `T_keep` constant | `constants.lua` — new `keep = { time = 30*24*h, posts = 500 }` next to `fork` | knob for boundary select |
| 2 | eager metadata fold | `common.lua` ~193 (post entry): add `blob`, `why`, `backs`; `get.lua`: resolve `--payload`/`--metadata` from `posts.lua` + blob store, not the commit | prerequisite for every later step |
| 3 | boundary select + shallow graft | new `chain/flatten.lua` (or maintenance path): pick newest checkpoint older than `T_keep` (either axis) as `c1`; write `.git/shallow`, `reflog expire`, `gc --prune=now` | keeps `c1` real hash |
| 4 | beg drop | `sync.lua` ~499: extend stale-beg cleanup to drop `refs/begs/*` below the boundary | else begs pin the ancestry |
| 5 | Blocker-1 guard | `sync.lua:54-61`: compare on the chain-id genesis hash (`#<genesis-hash>` dir name) instead of `rev-list --max-parents=0` | lets shallow peers sync |
| 6 | reject sub-boundary forks | `pre-receive` / `sync recv`: reject inbound branch forking below local boundary; blacklist repeat offenders | closes the DoS |
| 7 | rolling-auto trigger | invoke step 3 on a rolling `T_keep` schedule (e.g. post-`sync`) | only after 3–6 exist |

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

### Shallow graft at `c1` (this plan) — works

```
.git/shallow = { c1 }        -- c1 kept at its REAL hash, treated as parentless
G, a1, b1  -> pruned by gc    -- ancestors below c1 forgotten
      └─ c1 ── (future posts build on c1 normally)
```

`c1` keeps its real, network-shared hash — that is the point:
peers still agree on `c1` and merge-base against it. Commits
`a1` and `b1` (its ancestors) are **gone** — not renamed, not
preserved as commit objects, so nothing resolves them by their
commit-hash id anymore (that is what the blob-hash-in-metadata
section fixes for retrieval).

But their *tree content is not discarded by the graft*.
Freechains chains are non-bare working trees and every write is
a `git add` of a tracked file, so git trees **accumulate**: the
post payload file and `.freechains/likes/a1/...` were committed
in `a1`/`b1` and then rode forward unchanged into `c1`'s tree.
`c1`'s tree is untouched by the graft, so both files are **still
present**. What the graft drops is the *ancestor commit objects*
(and with them commit-hash addressability and the pre-checkpoint
GPG signatures), not `c1`'s tree.

Consequence for Track B: actually reclaiming payload storage
needs an explicit `git rm` on `c1`'s tree — it is **not** a free
side-effect of the graft. The reps/revoke effect is
independently summed into `c1`'s state tables, so the raw files
can go without losing derived state.

Contrast with `--orphan`: that would rebuild `c1` as a new
parentless commit with a *different* hash — same tree, but the
network no longer recognizes it. Shallow keeps the hash;
that is the whole reason it is chosen over orphan here.

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
