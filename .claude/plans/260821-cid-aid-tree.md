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

- S1 DONE (26/08/21): `tst/cid-edges.lua` pins today:
    - consecutive identical posts: DIFFERENT ids (backs
      differ) -- B's parents give the same shape
    - concurrent identical posts on the same tip: same aid
      AND same cid ALREADY (neutral dates collapse the
      commits into one); sync sees nothing new
    - => B's "idempotent collision" is byte-for-byte
      today's behavior; the identity question is closed
      empirically, not just by argument
- S2 DONE: git.lua empty-tree commit (msg + ref=false mint
  + GIT.tip); action.lua identity layer (read=message body,
  aid==cid, full=rev-parse ^{commit}, backs=walk parents)
- S3 DONE: post/like mint UNREFERENCED (ACTION.pre builds
  the commit) -> apply -> GIT.tip; act loses `backs`
- S4 DONE: consensus rewrite -- empty-tree check (new:
  "unexpected tree"), message parses as action, backs
  STRUCTURAL from parents, B7/filename/clean-add gone
- S5 DONE: get/list/rules/sync/abandon consumers; env.backs
  threads the structural backs into apply
- S6 DONE: tests reshaped (COMMIT crafts via message,
  CID/TREE identity, err-* crafts drop backs, lying-backs
  test REMOVED as impossible); FULL SUITE 40/40 GREEN
    - error renames: invalid action (was ...file/filename),
      unexpected tree (was expected clean add / 2-parent)
- DISK re-measure (1000 posts, packed window 50):
    - old (tree): 7002 objects (1001 c / 3001 b / 3000 t),
      1.17 MiB
    - new (msg):  3003 objects (1001 c / 2001 b / 1 tree),
      722 KiB
    - 57% fewer objects, 38% smaller pack; the 3000 trees
      and 1000 duplicate blobs were pure structure
    - remaining 2001 blobs are content: 1000 payloads +
      1001 state snapshots (git-state already packs these)
- FULL 10k SIM (wikimedia chat, 6541 actions):
    - packed floor: 9.65 MiB (vs tree-based git-state ~23
      MiB -> HALVED again); du 20 MB total
    - census: 12726 commits + 18417 blobs + 1 tree (blobs
      are pure content: payloads + state snapshots)
    - wall time 45.7 min, max RSS 26 MB -- FASTEST of all
      models (file 48 / bare-tree 57): minting = one
      commit-tree, no read-tree/update-index/write-tree
    - full arc: 15.3 GB -> 9.65 MiB (~1580x)
- S7 DONE (26/08/21): POSITIONAL message, no load, min fields
    - message = line-per-value, parsed by gmatch (NO Lua VM
      on untrusted bytes -> the whole T6c class is gone)
    - drop from the message: `time` -> commit DATE (%at),
      `sign` -> gpgsig (ssh.verify), `backs` already gone
    - discriminators that survive (not redundant): the kind
      verb, the target-type word, the SIGN of n
    - format (kind ∈ post|like|revoke; n>0/n<0 gives the
      dislike/unrevoke direction):
        post\n<payload-blob>
        like <n>\naction <aid>            (or author <pub>)
        revoke <n>\naction <aid>
        <trailing bare line> = the --why blob (votes, optional)
    - author id keeps its space: line = "author " .. pubkey,
      parse = first token is the type, rest is the id
    - determinism: actions now carry a real SIGNED date
      (cid depends on time, as it must); genesis + sync
      merges stay @0 -> nonzero date <=> action
    - ACTION.read: one `cat-file commit`, pulls DATE (author
      line) + body; builds the same t.{action,n,aid/author,
      blob,time} every caller uses -> callers unchanged
    - consensus: drop the sign-pin (B6) like backs (B7);
      `time` validated from the date, not the message
    - writers: commit-tree with GIT_AUTHOR/COMMITTER_DATE =
      time +0000 (was @0 for actions); serialize positional
    - get metadata: reconstruct/print from the parsed table
    - IMPLEMENTED; full suite 40/40. Notable in the port:
        - lua trap: `x and x:match()` truncates multiple
          returns to ONE value (bit the parser; fixed)
        - tests.lua MERGE/COMMIT mint with @0 (raw merges
          must match sync's neutral dates); COMMIT gained
          `date`
        - dissolved test classes: bad-target-type and
          fractional-n now fail PARSE ("invalid action");
          forge tests tamper the date/n line instead of the
          old table fields
        - cli-now premise inverted: post envelope date IS
          the action time; nonzero date <=> action (genesis
          keeps its own message at @0)

- S7 10k SIM (same input, clean A/B vs S6):
    - 46:10 wall (S6 45:41), RSS 26 MB: neutral
    - pack 9.96 MiB (S6 9.65): within delta-selection
      variance (+ dates vary per commit where @0 was
      constant); du 20 MB both
    - post-prune census IDENTICAL: 9634 commits + 18417
      blobs + 1 tree = 28052 (the S6 "12726 commits" note
      was pre-prune, counting 3092 rejected-beg loose)
    - => S7 is disk/time NEUTRAL; its wins are qualitative
      (no VM on untrusted bytes, minimal messages, log UX)
- S8 DONE (26/08/21): GENESIS positional too
    - message: <version>\n<nonce>\n<pioneer pubkey>...
      (zero labels; pioneers sorted -- fixes a latent
      `pairs` nondeterminism in multi-pioneer genesis)
    - closes the LAST `load` on remote bytes (a clone
      fetches the genesis from an untrusted peer): the
      T6c class is now fully gone, actions AND genesis
- S9 DONE (26/08/21): naming doctrine settled
    - USERS say `id`: CLI metavars (<id>), error strings,
      cli.md -- via `argument("id"):target("cid")`, the
      one-line mapping at the parse boundary
    - the PROTOCOL says `cid`: ARGS.cid and every internal
      var/param, env.cid, the vote-target field act.cid
      (message line `action <cid>`), metadata ["cid"]
    - `aid` survives ONLY as ACTION.aid, the is-this-an-
      action predicate; ACTION.cid alias deleted
    - rename traps found: env-key/dot-read mismatch, the
      consensus cid/aid shadow collapse, and a pubkey
      argument briefly labeled <cid> (like author targets)
- PENDING: guide/README transcripts
- NOTE: validated via worktree shim; hook needs `make
  install` for a native `make tests`
