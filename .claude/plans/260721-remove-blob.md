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

Cooperative removal is NOT viable while chains keep a working
tree. Prerequisite: **make chain repos bare** (no worktree ->
no resurrection surface, no checkout dependency). `get.lua`
already reads via `git show <hash>:file`, which works on bare;
sync's checkout steps would need rework.

## Payload transfer model (the core consequence)

Sparse-checkout fixes only the local worktree; it does NOT
change what the pack transfers. And the filter is
**all-or-nothing**: `filter=blob:none` omits EVERY blob — git
has no "omit exactly this one blob". So once a chain must be
served filtered (because a payload was removed), NONE of its
payloads ride the bulk pack.

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

## Bare-repo migration — scoping (paper only, 2026-07-21)

### Working-tree dependency map

The working tree is load-bearing across the codebase:

| Site | Op | Needs worktree |
|--------------------|----------------------------------|----------------|
| `post.lua:24,39`   | `io.open`/`cp` payload -> add    | yes |
| `post.lua:44,83`   | `git add` file / state           | yes (index+wt) |
| `like.lua:62,66`   | write like -> `git add`          | yes |
| `sync.lua:451`     | `git add` state                  | yes |
| `post.lua:72,96`   | `reset --hard`                   | yes |
| `like.lua:40`      | `merge -X ours`                  | yes |
| `sync.lua:320,378,389,415,441,447` | merge / `checkout` / reset | yes |
| 7x `commit -...`   | porcelain commit                 | index |

Reads are already worktree-independent: `get.lua` uses
`git show <hash>:file` from the object store.

### Option BARE (full) — impractical

A truly bare repo has no worktree/index; every write path above
would be rewritten to plumbing (`hash-object`, `update-index`,
`mktree`, `commit-tree`, `read-tree`, `merge-tree`). Touches
`post`, `like`, `sync`, `chains`. Large, risky, out of
proportion to the feature. Rejected as first choice.

### Option SPARSE — lighter; normal ops TESTED 2026-07-22

Keep the repo non-bare but sparse-checkout so the worktree holds
ONLY `.freechains/`, never the payload files:

```
git sparse-checkout init --no-cone
git sparse-checkout set  --no-cone '/.freechains/'
```

Effects:

- Payload files never materialize in the worktree -> `git add`
  cannot re-hash them -> **no resurrection**.
- `checkout` skips excluded (SKIP_WORKTREE) paths -> does not
  read the removed blob -> **no checkout error**.
- State writes under `.freechains/` still use normal porcelain
  (that subtree stays in the worktree).
- `get.lua` reads payloads from objects, unaffected.

Prototyped in /tmp (create + post + sync, NO removal yet):

- create: worktree ends up holding only `.freechains/`. OK.
- post: naive `git add <payload>` is REFUSED ("outside
  sparse-checkout"); `git add --sparse <payload>` works, then
  `git sparse-checkout reapply` drops it from the worktree.
  `git status` clean; `git show <hash>:file` still reads it.
- sync (no removal): payloads ride the pack normally; both
  `git push` and filtered clone transfer them. Sparse is
  local-only, transport unaffected.

So the ONLY code delta for normal operation is
`git add` -> `git add --sparse` + a `sparse-checkout reapply`.

Still to TEST (deferred):

- Does `merge --no-commit` / `reset --hard` behave under sparse
  when incoming commits add excluded payload files? Posts are
  additive (create-mode), so likely no conflicts — verify.
- That an actual `rm` of a payload STAYS gone across a full
  post/sync cycle under sparse (no resurrection path left).

### Verdict so far

SPARSE handles normal operation (verified). Remaining risk is
merge/reset under sparse + removal persistence. BARE stays the
fallback.

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

## Open questions

- **Finality window for physical deletion** (new, see above): how
  long must local REVOKED state hold with no new sync activity
  before an honest node `rm`s the loose blob? Needs its own rule,
  separate from the Rule 2 discount timer.

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
- [ ] **NEXT: scope the bare-repo plumbing rewrite** — replace
      `git add`/`checkout`/`reset --hard`/`merge --no-commit` in
      `post.lua`, `like.lua`, `sync.lua`, `chains.lua` with
      `hash-object`/`update-index`/`mktree`/`commit-tree`/
      `read-tree`/`merge-tree` equivalents
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
