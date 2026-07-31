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
| 3 | **Partial clone (`filter=blob:none`) + by-hash payload fetch** | yes | sync change only; payloads stay in tree |
| 4 | Sidecar payloads (content outside the tree) | yes | storage + signing rewrite |

## Chosen direction: partial clone (#3)

Primary because it serves peers with a removed blob **without**
changing hashes, storage, or signing:

- Served pack is commits + trees only (`filter=blob:none`), so
  a `rm`'d blob is never read -> serve succeeds.
- Client then fetches the payloads it wants BY EXPLICIT HASH
  from the sync peer (NOT git's promisor — see "How the
  per-payload fetch is done" below); a REVOKED payload has no
  provider -> peer lacks it (graceful, not fsck corruption).
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

Net: cooperative removal that "keeps git working" is REAL for
the fetch side, with **no storage or signing change** — partial
fetch + loose-blob config + tombstone-aware `get.lua`.

## Feasibility — TESTED 2026-07-21 (push side + resurrection)

Freechains syncs via `git push` (`sync.lua:10`); tested that too.

| Scenario                                          | Result |
|---------------------------------------------------|--------|
| full push, blob-removed node -> EMPTY receiver    | FAILS — `unable to read <blob>`, remote unpack failed |
| INCREMENTAL push (receiver already has the post)  | OK — delta above the cut, removed blob untouched |
| fresh receiver FILTERED fetch from the node       | OK — full DAG, payload absent |

Push mirrors fetch: full transfer needs the closure (fails);
incremental / filtered does not (works).

### CRITICAL: content-addressing RESURRECTS the blob

Removing the object-store copy alone is futile. Proven:

```
rm blob            -> GONE
git add .          -> PRESENT (resurrected: identical worktree bytes re-hashed)
rm blob + rm file  -> git add -> stays GONE
```

Any `git add` re-hashes still-present bytes back into the exact
same object. Payload must be gone from BOTH object store AND
working tree AND index.

### Blocker: chain repos are NON-BARE

`chains.lua:102` uses `git init -b main` (working tree), and
sync checks it out (`sync.lua:378` `checkout --detach`,
`sync.lua:415` `checkout main`). So:

```
payload lives in TWO places: object store + working tree
   rm object only     -> git add resurrects it
   git checkout main  -> needs blob to materialize file -> ERRORS
```

Looked at first like this required bare repos. See "Local
removal — scoping" below: the actual fix is narrower — a
per-path `--skip-worktree` bit set only on the removed file,
not a whole-repo migration.

## Payload transfer model (the core consequence)

Any local worktree trick (`--skip-worktree` included) fixes only
the local worktree; it does NOT change what the pack transfers.
And the filter is **all-or-nothing**: `filter=blob:none` omits
EVERY blob — git has no "omit exactly this one blob". So once a
chain must be served filtered (because a payload was removed),
NONE of its payloads ride the bulk pack.

Payloads therefore change how they move:

```
TODAY:  one pack = commits + trees + ALL payload blobs   (full replication)
DESIGN: one pack = commits + trees only  (filtered)
        each payload -> fetched later, per-post, BY HASH
```

Demonstrated 2026-07-21 (partial clone, then read):

```
git show HEAD:postC.txt   -> lazy-fetch postC blob from origin -> OK
git show HEAD~2:postA.txt -> lazy-fetch -> "not our ref" -> tombstone (revoked)
```

- metadata (commits+trees): one cheap filtered pack, full DAG;
- each payload: fetched on demand, by explicit hash, from the
  current sync peer (see per-payload-fetch section below);
- revoked payload: no holder serves it -> graceful tombstone;
  every other payload still transfers individually.

### Consequence: eager replication -> lazy fetch

| | Today | Removed-blob design |
|-------------------|--------------------|--------------------------|
| Payload transfer  | in the pack always | per-hash, on demand |
| Replication       | every peer holds all | only peers that fetched it |
| Availability      | any peer up        | a HOLDER up |
| Full archive peer | automatic          | must backfill payloads by-hash (plain unfiltered fetch re-demands the revoked blob -> fails) |

This tradeoff is intrinsic: git offers "omit all blobs, fetch
back individually", not "omit exactly this one". Accepting
removal = accepting lazy, per-post payload transfer.

### How the per-payload fetch is done (VERIFIED 2026-07-22)

Do NOT use git's promisor / `git backfill` machinery:

- promisor is config-bound to one `origin`
  (`remote.X.promisor`), but Freechains syncs explicit peer
  IPs, not a fixed origin;
- `git backfill` ABORTS on a missing blob (batch pass/fail,
  experimental) — but a revoked payload is *expected* absent,
  so backfill would error on exactly our case.

Instead fetch each payload BY EXPLICIT HASH from the current
sync peer, in a Freechains-controlled loop:

```
git fetch <peer-url> <blob-sha>     # + uploadpack.allowAnySHA1InWant on peer
   peer HAS it   -> exit 0, blob lands
   peer LACKS it -> "not our ref", exit 128 -> catch as tombstone
```

Tested: by-hash fetch from an ARBITRARY peer (not origin)
succeeds with `allowAnySHA1InWant`; a hash the peer lacks fails
per-request (exit 128) without corrupting anything. This dodges
both promisor pitfalls and matches the P2P model: any peer, by
hash, tolerating individual misses.

### Batch atomicity — TESTED 2026-07-22

A fetch REQUEST is all-or-nothing. Batched fetch of
`[present-blob, missing-blob]` in one request:

| request                          | result |
|----------------------------------|--------|
| batch of N hashes, ALL present   | OK — all N delivered in ONE round trip |
| batch [post5 present, post3 missing] | FAILS (exit 128); post5 does NOT land |
| per-blob post5 (present)         | OK, lands |
| per-blob post3 (missing)         | exit 128 |

Multi-hash fetch in a single request works (tested: 5 present
hashes -> all landed, one round trip). So the optimistic batch's
fast path IS efficient; only batches touching a missing blob
fall back to per-blob.

One missing object fails the whole request; its available
siblings are NOT delivered. Protocol-level (want-negotiation ->
single pack), so version-independent. `git backfill` (2.44+;
not on 2.43 dev box) batches the same way and aborts the same
way.

Consequence: efficiency and miss-tolerance are mutually
exclusive in one request. Use an OPTIMISTIC BATCH with per-blob
fallback:

```
1. fetch ALL wanted payloads in one request
2. success (nothing revoked in set) -> fast path, done
3. failure -> retry per-blob (or bisect):
   available ones land, revoked ones fail individually -> tombstones
```

Better than `git backfill`, which cannot do the fallback. One
more reason to use a Freechains-controlled fetch loop, not
git's promisor/backfill machinery.

Minor caveat to re-check on real (HTTP) transport: a
`filter=blob:none` clone from a source that HAS a given blob was
observed pulling that blob at clone time over local file://;
cloning from a blobless source pulled none. May be a
local-transport artifact — verify blobs are truly deferred on
the real serve path.

## Local removal — scoping (SUPERSEDES bare-repo migration, 2026-07-31)

Two problems were conflated under "bare-repo migration." Split
them:

1. **Lazy fetch** (a peer not eagerly downloading every payload)
   is pure transport: `filter=blob:none` fetch + the by-hash
   fetch loop, touching only `sync.lua` and `get.lua`. Zero
   changes to `post.lua`, `like.lua`, `chains.lua` — working
   trees stay exactly as-is for ordinary create/post/like/sync.
2. **Physically removing a payload this node already holds** is
   the only thing that needs special handling — and it turns out
   to be much narrower than "make the whole repo bare."

### Why full-bare was the wrong shape

Two concrete problems, not just "large and risky":

- `git mktree` validates by default that every referenced blob
  exists. Rebuilding a new commit's tree as "prior tree's entries
  + one new entry" (`git ls-tree HEAD^{tree} | ... | git mktree`)
  fails the moment ANY earlier entry references an already-removed
  blob — which is exactly what this feature causes on every post
  after the first removal. Every plumbing call touching "the
  existing tree" needs `--missing` or equivalent, a correctness
  burden threaded through every commit-creation path, not a
  one-off.
- A repo configured for `filter=blob:none` gets a `promisor`
  remote set as a side effect. Many otherwise-unrelated plumbing
  commands silently attempt to auto-fetch a missing object from
  that promisor remote when they touch one — uncontrolled, and
  exactly the mechanism already rejected for the deliberate
  by-hash loop ("Freechains syncs explicit peer IPs, not a fixed
  origin," per-payload-fetch section above). Going bare doesn't
  dodge this; the promisor bits get set by the partial-clone
  fetch side regardless of worktree.
- Full-bare's justification ("no worktree -> no resurrection,
  ever") was solving for "every payload, all the time." The
  actual need is "one path, at the rare moment it's removed."

### Actual scope: targeted `--skip-worktree`, not bare or sparse

Re-examining the original NON-BARE blocker's two components
(`chains.lua:102` working tree; `sync.lua:378,415` checkout):

- **Resurrection via `git add`**: every `git add` call in the
  codebase already targets an explicit path (`post.lua:44`'s
  `git add <file>`, `chains.lua:127`'s
  `git add .freechains/ ...`) — none does a blanket `git add .`.
  An already-`rm`'d payload sitting in the working tree is never
  swept back in by any *existing* write path; the resurrection
  risk demonstrated in the original prototype (`git add .`)
  doesn't actually occur on any current code path.
- **Checkout needing the missing blob** is the one real blocker
  (`sync.lua:378` `checkout --detach`, `415` `checkout main`) —
  checking out a commit whose tree includes the removed path
  needs to materialize that file.

Fix, applied only to the specific removed path, only at removal
time:

```
rm <object store copy of the blob>
rm <path>                                  -- working-tree file
git update-index --skip-worktree <path>    -- same bit sparse-checkout sets internally
```

`--skip-worktree` tells git: don't complain this path is missing,
don't try to materialize it on checkout, don't diff it. No
sparse-checkout subsystem, no cone-mode config, no policy change
for every other payload — this touches exactly the one file being
revoked. Everything else (chain creation, posting, liking, syncing
every other post) is unaffected: no plumbing rewrite of
`post.lua`/`like.lua`/`chains.lua`, no bare repo, no
`hash-object`/`mktree`/`commit-tree` anywhere in the ordinary
write paths.

### Still to verify

- `--skip-worktree` behavior under `merge --no-commit` /
  `reset --hard` (`sync.lua:449,507,563,569`) when the incoming
  side still carries the path present-but-unmodified — does the
  skip bit survive, or does merge try to re-materialize it? Same
  kind of test the earlier sparse prototype ran (2026-07-22), just
  scoped to one path instead of a `.freechains/`-only tree.
- Confirm the skip bit persists across the sync's checkout/reset
  cycle without needing to be re-applied each time (unlike
  sparse-checkout's cone patterns, which need `reapply`).

### Verdict

Drop the bare-repo migration entirely. `chains.lua`, `post.lua`,
`like.lua`, `sync.lua` keep their working-tree code exactly as
today. The only new code: at rm-time, delete the object + file
and set `--skip-worktree` on that one path; verify it survives
the existing merge/checkout paths in `sync.lua`.

## Sync consistency: hard-fail on a non-revoked miss (2026-07-31)

The optimistic-batch + per-blob-fallback loop (transfer model
above) tolerates misses — but not all misses mean the same
thing, and conflating them corrupts local state:

- hash IS in the local revoked set -> expected miss -> tombstone,
  fine;
- hash is NOT in the local revoked set -> unexpected miss (peer
  dropped a live payload, network fault, or a malicious peer) ->
  this must be a hard error, not a tombstone.

Critically: "not in the local revoked set" must be checked
against **local** state (this node's own `.freechains/revokes/`
sums, reps.md:287-307), never inferred from the peer's silence —
a peer simply not having a hash is not proof it was ever revoked.

So the sync procedure is:

1. compute the wanted-hash set for the incoming delta;
2. cross-reference against the local revoked set;
3. optimistic batch-fetch everything;
4. on batch failure, retry per-blob;
5. any per-blob miss whose hash is **not** locally revoked ->
   abort the sync before any ref/HEAD update. No partial
   merge/reset/checkout applied. The chain stays exactly as it
   was pre-sync.
6. only misses whose hash **is** locally revoked are tolerated
   as tombstones, and the sync completes normally.

This is what makes "ignore revoked objects at the protocol
level" (transfer model above) safe: revocation is the *only*
sanctioned reason a fetch is allowed to come back incomplete.
Anything else is a failure, and local consistency wins over
completing the sync.

## Gated unrevoke: guaranteed availability at flip time (2026-07-31)

`unrevoke` (and, per reps.md:278, a community `like` cast on a
REVOKED post, which also counts as an unrevoke) is a signed vote
commit — pure integer math over `.freechains/revokes/` sums,
blind to payload presence (reps.md:254-312). Nothing today stops
a node from casting `unrevoke` without holding the payload, which
would let a post transition out of REVOKED while the bytes are
gone everywhere — a promise the network cannot honor.

Un-revoke must instead be a **guarantee**, not a hope: the source
casting the vote must not be able to create it unless the blob is
actually available.

- Before building/signing the `unrevoke` (or REVOKED-post `like`)
  commit, the local node must materialize the payload: check the
  local object store, and if absent, run the by-hash fetch loop
  (transfer model above) against known peers.
- Only on success does the command proceed to create and sign the
  commit.
- On failure it refuses, same shape as every other guarded
  command:

  ```
  ERROR : chain unrevoke : blob unavailable
  ```

This guarantees that **at the moment a post leaves REVOKED, at
least one peer (the caster) provably holds the payload** —
availability was a precondition of the commit existing at all,
not an afterthought. It does not promise the blob survives
forever after that (the caster could `rm` it again later — same
cooperative ceiling as the rest of this design), but it closes
the hole of an unrevoke entering the DAG while nobody anywhere
has the bytes.

### RESOLVED 2026-07-31: `like`-as-unrevoke gate

Same gate applies to a `like` cast while the target post's local
state is REVOKED (reps.md:278: a positive `like` also counts as
an others-channel unrevoke) — it must materialize the blob first
or refuse, same as explicit `unrevoke`. A `like` on an
already-ACCEPTED post is untouched: ordinary reputation action,
no availability promise at stake.

### Found while resolving: gating alone cannot make deletion safe

The revoke/others sum is a commutative, order-independent replay
(reps.md:309-312: "likes cast *before* a revoke count just the
same"). So a post can flip REVOKED -> ACCEPTED purely by a node
re-deriving the sum from commits it already had, or already-signed
likes arriving late in sync — with no NEW commit being cast at
that moment. Gating only fires when a commit is created; it
cannot intercept re-acceptance that happens as a passive side
effect of sync recomputing an existing sum from data already on
disk.

Consequence: physical `rm` must NOT be wired to "the instant this
node's local sum first computes REVOKED." A node that deletes
eagerly on that signal can see the sum swing back non-negative
moments later as more votes sync in — blob already gone, no
gated cast ever happened for that swing.

Resolution: **decouple physical deletion from the Phase-1
display-hide computation.** Display-hide stays instantaneous,
recomputed on every commit, as today (`260721-revoke.md`).
Physical removal (this plan) needs its own finality trigger: only
`rm` after the local REVOKED state has held through a settling
window with no new sync activity, not on the first commit that
computes it. Checked `reps.md` for an existing quiescence
mechanism to reuse — none exists; the only 0-12h window in that
doc is the unrelated post-cost discount timer (reps.md:135-153).
This finality window is a new mechanism to design, not something
already covered elsewhere.

## Finality window design (2026-07-31)

The two revoke channels (reps.md:287-307) have different risk
profiles, so they get different treatment:

### Author channel — no window needed

`p.revoke.author < 0` can ONLY be moved by a fresh commit signed
by the author (reps.md:294-296: "only the author's own unrevoke
lifts it"). That commit is already gated (must materialize the
blob before signing, see above). So nothing about a lagging or
partial sync view can silently flip this channel — it is not a
sum a node can be "wrong about" the way a multi-caster sum can.
Once this node has pulled the author's full commit history for
the post, `p.revoke.author < 0` is as final as anything gets here.
**Eligible for immediate `rm`**, no settle timer required.

### Others channel — SIMPLIFIED 2026-07-31: flip once at end of sync

`p.revoke.others` is a running sum over many independent
signed casters (reps.md:290-292). A node with a partial DAG view
can compute a currently-negative sum that was never the network's
true converged answer — more already-existing, not-yet-pulled
positive votes could still land and push it non-negative. This
isn't a legitimate community revocation getting reversed; it's a
node treating an incomplete view as ground truth for an
irreversible physical action.

Originally designed as a persistent `local/revoked.lua` table +
calendar `SETTLE` timer (see history). Simplified after checking
what actually motivated it:

- **Never act mid-replay** — intrinsic, and needs no timer at all.
  The engine walks the git log in date-order and recomputes
  incrementally, same pattern as the Rule 2 engine (reps.md:429-
  441). During that walk a sum can dip negative and climb back
  positive purely from processing order, even over commits this
  node already has in full — no network involved. Fix: act only
  ONCE, on the FINAL sum after this sync's full pulled delta has
  been replayed, never on an intermediate crossing mid-walk.
- **Hedge against a not-yet-synced honest peer** — was going to be
  the calendar buffer's job. Checked whether the risk that
  actually justifies a standalone timer (cheap malicious
  oscillation forcing repeated rm/re-fetch churn) is real: every
  vote in the table above costs `-n` to the caster (reps.md:269-
  274); the only free move in the whole system is the author's own
  downward self-revoke (reps.md:284-285, 299-300) — every upward
  move (`like`, `unrevoke`, including the author's own) always
  costs. Forcing an oscillation needs an upward move each cycle,
  so it is bounded by the attacker's reps balance, the 30-rep cap
  (Rule 4.b), and +1/day regen — not free spam. That kills the
  standalone-timer justification.
- What's left is a non-adversarial residual: an honest, merely-
  slow peer's vote not yet received. Accepted as-is — it's the
  same cooperative-not-guaranteed ceiling the whole plan already
  declares (NON-GOAL section above). A false-negative `rm` from a
  lagging view recovers the same way anything else here does: the
  next read lazy-fetches by hash (transfer model above) and
  succeeds if any peer still holds the bytes.

**Resulting rule** (no persistent state, nothing tracked between
syncs):

- at the end of processing a sync's pulled delta (after the full
  incoming batch has been replayed, not per intermediate commit),
  recompute the final `others` sum for every post touched by that
  batch;
- `rm` the loose blob for any that land negative (community or
  author channel) and are still locally present;
- a post whose sum recomputes non-negative needs no explicit
  restore step — if this node had already `rm`'d it in some prior
  sync, the next read simply lazy-fetches it by hash, same as any
  other on-demand payload fetch.

No `local/revoked.lua`, no `SETTLE` constant, no completed-sync-
round bookkeeping — "act once, at the end of this sync's replay"
is the whole rule.

## Open questions

- Full initial push/clone still needs the closure -> a chain
  with a removed payload can only onboard new peers via
  FILTERED transfer. Confirm both push and fetch paths in
  `sync.lua` can be made filtered, or that sync flips to
  fetch-pull for such chains.
- ~~Promisor identity~~ RESOLVED 2026-07-22: skip git promisor;
  fetch payloads by explicit hash from the current sync peer
  (`git fetch <url> <sha>` + `allowAnySHA1InWant`). See transfer
  model above.
- Archive backfill: use OPTIMISTIC BATCH + per-blob fallback
  (see transfer model). Big single fetch when nothing revoked;
  on failure, retry per-blob so available payloads land and
  revoked ones tombstone. NOT `git backfill` (batches, aborts
  on missing, promisor-bound, needs 2.44+). Batch atomicity
  proven 2026-07-22.
- Availability: lazy per-post transfer means a payload dies if
  all its holders go offline — acceptable for a content system?
- Wire representation of a tombstone (absent vs explicit
  marker) so peers distinguish "revoked" from "not yet synced".
- Back-compat: existing chains embed payloads in the tree and
  transfer full closure — migration/opt-in path.

## Progress

- [x] Fetch/clone side feasible (tested 2026-07-21)
- [x] Push side tested: incremental/filtered OK, full FAILS
- [x] Found: blob resurrects via `git add` (content-addressing)
- [x] Found: chain repos non-bare -> resurrection + checkout
      blocker
- [x] Scoped bare-repo migration: full-bare impractical;
      SPARSE-checkout is the candidate (paper, 2026-07-21)
- [x] Payload transfer model proven (2026-07-22): filtered
      metadata pack + by-hash fetch; batch atomic; multi-hash
      OK; optimistic-batch + per-blob fallback
- [x] SPARSE normal ops prototyped (2026-07-22): create/post/
      sync work; `add --sparse` + `reapply` is the only delta
- [x] DECISION 2026-07-31: SPARSE rejected, BARE accepted — the
      by-hash fetch machinery is required either way, so sparse's
      lighter-cost argument no longer holds, and bare's no-worktree
      structural guarantee beats sparse's open merge/reset risk
- [x] REVERSED 2026-07-31 (same day): bare dropped entirely. Two
      real problems found: `mktree`'s default existence check
      breaks the moment any prior tree entry is an already-removed
      blob (i.e. on every post after the first removal); partial-
      clone promisor bits can trigger silent auto-fetch from
      unrelated plumbing calls. Also realized lazy-fetch
      (transport) and physical local removal are separable — only
      the latter needs anything special, and it's narrow: a
      per-path `git update-index --skip-worktree` at rm-time, not
      a whole-repo bare or sparse migration. `post.lua`/`like.lua`/
      `chains.lua` keep their working-tree code unchanged.
- [x] DECISION 2026-07-31: sync must hard-fail (no ref/HEAD
      update) on any per-blob miss whose hash is not in the LOCAL
      revoked set; only locally-known-revoked misses tombstone
- [x] DECISION 2026-07-31: unrevoke (and REVOKED-post `like`,
      reps.md:278) must be gated — refuse to create/sign the
      commit unless the local node first materializes the blob
      (local store or by-hash fetch); guarantees at least one
      holder exists the moment a post leaves REVOKED
- [x] RESOLVED 2026-07-31: `like`-as-unrevoke gate confirmed —
      same precondition as explicit `unrevoke`, scoped to
      currently-REVOKED targets only
- [x] FOUND 2026-07-31: order-independent sum replay means a post
      can flip back to ACCEPTED with no new gated commit at all ->
      physical `rm` needs its own finality/settling window,
      decoupled from the instantaneous Phase-1 REVOKED computation
- [x] DESIGNED 2026-07-31: finality window — author channel needs
      none (only a fresh gated commit moves it); others channel
      needed protecting against mid-replay oscillation
- [x] SIMPLIFIED 2026-07-31: dropped the persistent
      `local/revoked.lua` + calendar `SETTLE` timer — oscillation
      attacks always cost the caster reps (only the author's own
      downward self-revoke is free, reps.md:284-285,299-300), so
      the standalone-timer justification doesn't hold; rule is now
      just "rm once, on the final sum after this sync's full
      replay" — no state tracked between syncs
- [ ] **NEXT: verify `--skip-worktree` survives `merge --no-commit`
      / `reset --hard` in `sync.lua` (lines 449,507,563,569) for a
      single removed path** — same test shape as the earlier
      sparse prototype (2026-07-22), scoped to one path instead of
      a whole `.freechains/`-only tree
- [ ] Loose-object git config
- [ ] `uploadpack.allowFilter` + filtered fetch in `sync.lua`
- [ ] `get.lua` tolerates absent payload -> tombstone
- [ ] `rm` revoked loose blob on honest nodes
- [ ] Implement hard-fail-on-unexpected-miss check in sync
- [ ] Implement gated unrevoke (+ decide on `like`-as-unrevoke gate)
- [ ] Doc: cooperative-only guarantee (no global erasure) — still
      true for pre-flip holders who choose not to cooperate; the
      gate above only strengthens the flip moment, not the ceiling
- [ ] Migration for full-closure chains

## Cross-references

- `260721-revoke.md` — Phase 1 (display-level revocation);
  this plan is its Phase 2.
- `prune.md` — `--orphan` flatten (rejected rewrite option).
- `reps.md:243,250` — revocation rule; "not retransmitted"
  downgraded here to cooperative.
- `signing.md`, `git.md` — relevant to the sidecar alternative.
- `sync.lua:10,23` — vanilla git push/fetch transport.
