# Scripts: Programmable Chains

# Status: Design (revised 2026-09-25)

- supersedes the first draft ("smart contracts": genesis
  Lua that accepts or rejects blocks)
- the revision follows from where payloads live and from
  revoke; the first draft ignored both

# Context

- the wish: programs embedded in the chain that run on every
  new post, reject what does not belong, and build things
  from what does (sites, indexes, feeds)
- the motivating case: an academic department (UERJ) drops
  a thesis as a post, the chain becomes a self-publishing
  repository of HTML pages
- everything in Lua

# The fact that decides the design

- payloads are OFF the DAG: a post commit names a blob hash,
  the bytes sit at `refs/payloads/<cid>`, fetched in a
  separate pass AFTER `main` is replayed (260903-128KB.md)
- so replay never sees the bytes, and a post with missing
  bytes is ALREADY a valid state
- revoke makes it permanent: a revoked post loses its anchor
  (`like.lua` REMOVAL, `sync.lua` reconcile), the bytes are
  never fetched again (negative refspecs), `get payload`
  refuses them
- consequence: NOTHING that reads a revocable payload can be
  a consensus rule; a late peer cannot recompute it
- this is not a script limitation but the price of revoke:
  a system with a right to be forgotten cannot derive
  consensus from erasable content (Ethereum never erases)
- the test is the one in TODO.md "Per-chain constants":
  does the value derive `G`? scripts over revocable bytes
  never may

# What dies

- an Ethereum-style contract: a verdict that decides DAG
  membership, reps, or credit from the content
- a global state machine over payloads (balances, counters):
  two peers never agree once one payload is revoked
- a verdict that reads OTHER posts' payloads: a later revoke
  flips the result, peers diverge

# What stays: scripts as LOCAL policy

- validation
    - L1 `post`: refuse to publish what the script rejects
    - L3 `recv`: the post stays in the DAG (author paid, it
      consolidates), the peer drops the anchor and never
      hosts the bytes; same loop as 128 KB and revoked scan
    - "reject the block" becomes "reject the bytes"
    - with the withholding tracker, a post every peer
      rejects is invisible in practice
- side effects: `chains/<name>/out/`
    - the site, the indexes, the feeds; regenerable, local,
      no replay dependency
    - aggregates (an index of all theses) live HERE only,
      regenerated from the surviving payloads
- a local script that fails determinism yields a wrong site
  on one machine; a consensus script that fails determinism
  forks peers, and "dislike it away" does not undo a fork:
  keeping scripts local is what makes "determinism cannot
  be enforced" acceptable
- reputation and consensus stay in the protocol (unchanged)

# Linking with revoke

- verdict reads its OWN payload only; metadata and the DAG
  are fine (replayed), other payloads are not
- missing bytes: skip the script, the post passes; a revoked
  post is one the community already judged
- `out/` follows the anchor crossings
    - REMOVAL (entered revoked): delete `out/<cid>/`
    - LIFT (left revoked, bytes back via `--file` or sync):
      regenerate
    - 260818-payloads.md S6.2 (`apply` emits anchor events)
      is the natural hook: one path for `like` and `sync`
    - so a script must scope its products per cid, removal
      is then mechanical; aggregates regenerate
- script API: a revoked payload reads as `nil`, as `get`
  refuses it; authors handle `nil`

# Validation moves to the genesis: a payload FORMAT

- validation does not need code; a declarative format in
  the genesis does it better
    - MIME, magic bytes, max size, required fields
    - a fixed vocabulary, never author-supplied patterns
      (`%1` backreferences backtrack quadratically on 128 KB)
- determinism for free, no sandbox, no resource limits
- fits genesis.md: a positional `format:` section after
  `pioneers:`, canonical, parsed by match, in the hash, so
  part of the chain identity; `get metadata genesis` shows it
- ONE anchoring helper: today the anchor is written in
  `post.lua` (publish), `like.lua` (LIFT, `--why`) and
  `sync.lua` (restore); a single check of size and format
  before every `update-ref refs/payloads/` implements L1, L3
  and the format in one pass; nonconforming bytes never get
  an anchor, `sweep` reaps them
- revoke: nothing changes; revoked has no bytes to check,
  bytes coming back pass the same helper
- TODO.md split needs a third category: genesis holds what
  derives `G` (replayed), config holds local policy; a
  format is chain-specific so it must be SHARED, but it is
  not replayed; the genesis is the only shared immutable
  place, so it may carry declared-but-not-replayed policy
  (a peer ignoring it hosts junk, nobody forks)

# Protected posts: payload IN the commit tree

- the inversion: instead of adapting scripts to revoke,
  remove revoke from the posts a script needs
- naive form breaks: a rule in `apply` that asks the
  validator about the TARGET needs the target's bytes at
  replay; peers without them cannot decide the revoke
- the form that closes: a protected post carries its payload
  in the commit TREE (today every commit uses the empty tree)
    - git fetches the tree with the commit, atomically: no
      "missing bytes" state exists for it
    - replay SEES the bytes: size and format run in `apply`
      as consensus rules for these posts (the 128 KB plan's
      "replay never sees the bytes" premise no longer holds
      for them)
    - revoke refused in `apply`, one line beside
      `"invalid target : expects 'action'"`; deterministic,
      and there is nothing to unanchor anyway
    - scripts over protected posts reproduce on every peer:
      the same site everywhere
    - same mechanism the first draft used for the script
      itself (a blob in the genesis tree)
- two post classes coexist
    - `post ; <blob>`: revocable, off-DAG, local policy (today)
    - `keep ; <tree>` (name open): permanent, consensual
    - the genesis `format:` says what a `keep` must satisfy;
      a nonconforming `keep` is refused in replay, as a vote
      with a bad `n` is
- costs, to be accepted with open eyes
    - no right to be forgotten for these posts: the free
      self-revoke in `rules.lua` exists for exactly that; the
      post form IS the author's consent, the genesis section
      IS the chain's
    - illegal content that passes the format is permanent;
      only dislike or leaving the chain remain; fine for an
      institutional repository, not for open chains
    - every peer carries every protected byte forever: disk,
      clone bandwidth; 128 KB becomes a HARD rule for them
    - the validator is in consensus, so it cannot be a Lua
      function: that brings back determinism, sandbox and
      resource limits, now with no escape valve since nothing
      can be revoked; declarative format only
- what it does and does not solve
    - solves the revoke coupling entirely, and yields
      consensus rules over content as a bonus
    - does NOT solve code in consensus: scripts remain local
      side-effect generators, now with the same input on
      every peer

# Scripts themselves

- genesis scripts: blobs in the genesis commit tree, never
  revoked, replaced only by a new chain
- user-submitted scripts: a post whose payload is the script
    - removal is by REVOKE, not dislike: dislike only hits
      the author's reps, `is_revoked` is what removes content
    - a revoked script stops running; forward-only, earlier
      products stay (as the first draft wanted)
- consent-based execution: an author spends 1 like to run a
  user script, `why` is the argument
    - the like is on the DAG; the execution is local, on
      whoever opts in
    - `why` is a payload at `refs/payloads/<cid>`: revoking
      the vote erases the argument, the run is then
      irreproducible; local consequence, never consensus
- sandbox still needed against MALICIOUS code (threats.md
  T6c), even for local scripts: `load(src, "=name", "t", {})`
  as elsewhere; TODO.md "Sandbox `STATE.read` too" first

# Use case: UERJ

- genesis `format:`: `application/pdf`, max size
- theses as protected posts (`keep`) if the department wants
  the repository permanent and reproducible; as plain posts
  if it wants revoke
- the HTML generator is a local script writing
  `out/<cid>/`, plus an index regenerated from the survivors

# Order of work

1. TODO.md sandbox of `STATE.read` (defense-in-depth, and
   the same `load` shape scripts will use)
2. the anchoring helper (size, format) and the genesis
   `format:` section: 260903-128KB.md L1/L3 folded in
3. `out/` bound to REMOVAL/LIFT (with 260818-payloads.md S6.2)
4. local scripts: API (own payload, metadata, DAG; `nil` for
   revoked), the `post`/`recv` hooks, `out/` layout
5. protected posts (`keep`), only when a case asks for
   permanence; prototype UERJ on plain posts first

# Open

- `keep` in `action.lua`: message shape, signing envelope,
  replay; a real protocol change
- an on-DAG header (title, year) as part of `format:`, so an
  index survives the revoke of a body: public forever, so
  metadata only; not before a case needs it
- resource limits for LOCAL scripts (a runaway generator
  only hurts its peer, but hurts it)
- `out/` across nodes: not synced; each peer regenerates
