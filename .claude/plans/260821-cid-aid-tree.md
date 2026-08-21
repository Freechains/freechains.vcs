# 260821-cid-aid-tree

- actions move INTO the commit message: aid == cid, no trees
- the fixed point of the design trajectory: neutral dates
  made commits deterministic, B7/B8 made parents
  authoritative, bare killed the worktree, genesis moved
  into a message -- this generalizes that to every action
- wire-breaking (fine: no back-compat is standing policy)

# Design

- a chain is a signed commit DAG; three primitives only:
    - COMMITS: the protocol (actions; merges have empty
      messages; genesis message carries the genesis table)
    - BLOBS: out-of-band bytes (payloads, states)
    - REFS: anchors (payloads, states, begs, genesis)
- an ACTION is a commit whose message is the action table
    - id: the cid itself (aid == cid, one id space --
      states/payloads/begs already keyed compatibly)
    - a MERGE is a commit with an empty message: transparent
- tree: the constant empty tree in EVERY commit
- `backs` field DROPPED: the commit's parents ARE the backs
  (merges transparent, as ACTION.backs already computes);
  git's Merkle binds full ancestry stronger than backs did

# What dissolves (not checked -- gone)

- aid<->cid maps: ACTION.aid (diff-tree/commit) and
  ACTION.cid (log --diff-filter walk) become identity;
  these are the replay hot spots of the perf plan (P2/P4)
- B7 (backs == parents): nothing left to claim or lie about
- "invalid action filename": a message cannot misname itself
- GIT.commit tree machinery: no merge-tree, no read-tree/
  update-index/write-tree; commit = commit-tree EMPTY -p ...
- bucket dirs actions/xx/ (the O(n^2) tree workaround)
- tree objects on disk (~1/3 of the sim's 66586 objects)

# Identity: nothing of substance lost

- today: aid = hash(file) = hash(content + backs)
       = content + ancestry
- B: cid = hash(message + parents + neutral dates)
       = content + ancestry. Same binding, via git's Merkle
- dup-skip degenerates CORRECTLY: same content + same
  parents = literally the same commit (idempotent); different
  parents = different backs = different aid today too
- VERIFY: the beg flow (beg commit on its own ref, beg-like
  merges it -- the beg's cid stays its id) and replay's
  "same action arrived earlier" path

# Flow change (the one real reshape)

- id exists only at commit time ->
    1. write message tmp; `commit-tree` UNREFERENCED
       (loose commit object; parents already known)
    2. `apply` with the cid
    3. on success: `update-ref HEAD` (+ payload anchor)
- rejected action = one unreferenced loose commit, gc-able:
  exactly today's loose-blob situation
- signing: `commit-tree -S` covers the message = the action

# Consumer audit (to reshape)

- consensus.lua: "clean add of one named file" ->
  "message parses as action table" (same data-not-program
  load, T6c); merge check = empty message + 2 parents
- action.lua: read = cat-file commit + body after `\n\n`
  (serial emits no blank lines: boundary unambiguous;
  gpgsig continuation lines stay in the header block);
  full = `rev-parse <prefix>^{commit}` (native
  disambiguation); aid/cid = identity; backs = walk parents
  until non-empty message (cat-file, no diff-tree)
- post/like: build message; the act table loses `backs`;
  mint via unreferenced commit-tree (flow above)
- sync: voided listing (log --no-merges) -> filter by
  non-empty message; replay reads messages
- abandon: ACTION.cid = identity; range aids = messages
- chains.lua: genesis already message-based -- keep
- tests: helpers (CID, GENESIS ok) + expectations broadly

# What it does NOT fix

- the payload dance (refs, wildcard fetch, reconcile) is
  untouched: payloads are out-of-band in every design

# Edges to verify with tests first

- same author, same text, same tip, same --now: same cid ->
  idempotent second post (today: same aid; check behavior)
- message bytes: serial is text, no NULs, no blank lines --
  assert on read anyway (untrusted input)
- prefix collision with blob ids: rev-parse ^{commit}
  disambiguates
- `git log` UX: messages ARE actions now (a feature)

# Rejected alternatives (recorded)

- C hash-in-message, blob outside trees: blob is UNREACHABLE
  (message text is opaque to git) -> gc eats the chain and
  push/fetch stops carrying actions; would generalize the
  payload-ref disease (O(chain) advertisement) to all actions
- D tree-of-one (blob kept, single-entry tree): sound,
  minimal, but a way-station -- keeps aid<->cid maps, B7,
  and per-action tree+blob objects. Rebuild-into-B later.

# Steps

- S1: tests first: craft the edges above vs TODAY's code
- S2: GIT.commit -> empty tree + message; action.lua
  identity layer
- S3: post/like flow (unreferenced mint -> apply -> ref)
- S4: consensus/replay validation reshape
- S5: sync/abandon consumers; drop backs everywhere
- S6: tests + guide/README transcripts; measure disk again
  (expect ~1/3 fewer objects)
