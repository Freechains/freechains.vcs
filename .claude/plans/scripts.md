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

# What dies, what splits

- dies: any consensus verdict over a REVOCABLE payload, and
  any global state machine over payloads (balances,
  counters): two peers never agree once one payload is gone
- dies: a verdict that reads OTHER posts' payloads: a later
  revoke flips the result, peers diverge
- splits: the first draft's single "script" becomes two
  kinds of code with two trust levels
    - a CONTRACT builds things from content: local, free,
      best-effort; wrong on one machine hurts one machine
    - a VALIDATOR decides whether a post enters and becomes
      irrevocable: consensus, deterministic by construction,
      budgeted; and it can only exist for posts whose bytes
      are IN the DAG (`keep`, below)
- "dislike it away" undoes a bad contract, never a fork:
  that is why contracts stay out of `apply` and validators
  are held to the rules of a consensus rule
- reputation stays in the protocol: neither kind touches reps

# Genesis tree: two directories, two trust levels

- the genesis commit carries a TREE (today the empty tree)
    - `validators/<name>.lua`: CONSENSUS code, run in `apply`
    - `contracts/<name>.lua`: LOCAL code, run on accepted posts
- the tree is under the genesis hash: the scripts are part of
  the chain identity, never revoked, replaced only by a new
  chain
- the directory IS the consensus boundary: what a file may
  read, what it may cost, and what breaks when it misbehaves
  all follow from which directory it sits in
- `chains add --scripts <dir>` (name open) commits the tree;
  `chains add clone` gets it with `refs/genesis`; NEVER
  `dofile`d (threats.md T6c): `load(src, "=name", "t", ENV)`
  with an explicit `ENV`, as `pioneers()` already does

# Validators: refuse revoke, in consensus

- the inversion: instead of adapting scripts to revoke,
  remove revoke from the posts a script needs
- naive form breaks: a rule in `apply` that asks a validator
  about the TARGET of a revoke needs the target's bytes at
  replay; peers without them cannot decide
- the form that closes: a protected post carries its payload
  in its own commit TREE, and the validator runs ONCE, at the
  post, not at the revoke
    - `keep <name> ; <tree>` (shape open): a post asking to be
      protected by `validators/<name>.lua`
    - git fetches the tree with the commit, atomically: no
      "missing bytes" state exists for a `keep`
    - replay SEES the bytes: `apply` runs the validator over
      them; `true` accepts and marks the entry (`keep=true`
      in `G.actions`), `false` REFUSES the post, as a vote
      with a bad `n` is refused; unknown `<name>` refuses
    - a later `revoke` on a `keep=true` target is refused in
      `apply` from the FLAG alone, one line beside
      `"invalid target : expects 'action'"`: deterministic,
      no bytes needed at revoke time, and nothing to unanchor
    - self-revoke refused too: the `keep` form IS the
      author's consent, the genesis tree IS the chain's
    - dislikes unaffected (they hit the author, not the
      content); rule 1.b credit always holds
- plain `post ; <blob>` never meets a validator at consensus
  level: its bytes are off the DAG and revocable, as today;
  two classes coexist
- validators are genesis-only; a user-posted validator would
  be consensus code nobody agreed to
- what a validator must be, now that it is consensus code
    - deterministic BY CONSTRUCTION, not by good will: the
      `ENV` it loads with offers only pure primitives; no
      `os`, `io`, `math.random`, no clock, no `require`
    - no `pairs`: Lua 5.4 seeds string hashing per process,
      so table order differs between peers; the API gives
      sorted iteration only (`serial(G)` already sorts for
      the same reason)
    - an INSTRUCTION budget, not a time budget:
      `debug.sethook(f, "", N)` counts VM instructions, the
      same on every peer running the same Lua; a validator
      over budget is `false`, deterministically; a wall
      clock would fork peers
    - the Lua version pinned: instruction counts and stdlib
      behavior are per version; genesis line 1 already
      carries a version, it must cover the VM too
    - input is the payload bytes plus the post's metadata
      (member, time, backs); never other payloads, never `G`
      beyond what `apply` exposes to rules today
    - a buggy validator forks or bricks ONE chain, whose
      creator already is its trust root (pioneers,
      dictators); acceptable, as a bad genesis is
- declarative checks (MIME, magic bytes, size, fields) are a
  LIBRARY the validators call (`FMT.mime`, `FMT.size`), not
  a separate mechanism; a trivial validator is one call
- 128 KB is a HARD rule for a `keep`: bytes are in history
  and every peer carries them; the validator or `apply`
  refuses above `C.post.size`
- costs, to be accepted with open eyes
    - no right to be forgotten for a `keep`: the free
      self-revoke in `rules.lua` exists for exactly that
    - illegal content that passes a validator is permanent;
      only dislike or leaving the chain remain; fine for an
      institutional repository, not for open chains
    - every peer carries every `keep` forever: disk, clone
      bandwidth
    - the 128 KB plan's "replay never sees the bytes" premise
      no longer holds for `keep`; its L1/L3 stay for plain
      posts
- what it does and does not solve
    - solves the revoke coupling entirely for `keep`, and
      yields consensus rules over content as a bonus
    - contracts stay local: a validator decides membership
      and irrevocability, never reps or side effects

# Contracts: side effects, local

- run on every ACCEPTED post, `keep` or plain, after `apply`
  on the poster's node and on `recv` on every other; never
  inside `apply`, never a verdict
- output under `chains/<name>/out/<cid>/`, plus aggregates
  regenerated from the survivors
- input: the post's payload (`nil` when revoked or missing,
  as `get` refuses it), its metadata, the DAG, and `G`
    - over a `keep` the input is the same on every peer, so
      the site is the same everywhere
    - over a plain post it is best-effort, as before
- `out/` follows the anchor crossings of plain posts
    - REMOVAL (entered revoked): delete `out/<cid>/`
    - LIFT (bytes back via `--file` or sync): regenerate
    - 260818-payloads.md S6.2 (`apply` emits anchor events)
      is the natural hook: one path for `like` and `sync`
    - a `keep` never crosses: its products stay
- also usable as LOCAL validation of plain posts: L1 in
  `post` refuses to publish, L3 in `recv` drops the anchor
  and never hosts the bytes; "reject the block" becomes
  "reject the bytes"; with the withholding tracker a post
  every peer rejects is invisible in practice
- a local contract that fails determinism yields a wrong
  site on one machine, nothing more: the same `ENV` sandbox
  as validators against MALICIOUS code (T6c), but no budget
  and no determinism rule
- user-submitted contracts: a post whose payload is the script
    - removal is by REVOKE, not dislike: dislike only hits
      the author's reps, `is_revoked` is what removes content
    - a revoked contract stops running; forward-only, earlier
      products stay (as the first draft wanted)
    - consent-based execution: an author spends 1 like to run
      it, `why` is the argument; the like is on the DAG, the
      run is local, on whoever opts in
    - `why` is a payload at `refs/payloads/<cid>`: revoking
      the vote erases the argument, the run is then
      irreproducible; local consequence, never consensus
- a user-submitted contract can only be a plain post: its
  own code must stay revocable

# Use case: UERJ

- `validators/thesis.lua`: `FMT.mime "application/pdf"`,
  `FMT.size`, maybe a first-page pattern; budgeted
- theses as `keep thesis`: permanent, reproducible, the
  repository the department wants
- `contracts/site.lua`: thesis -> `out/<cid>/index.html`,
  plus a regenerated index; local, same on every peer since
  every input is a `keep`
- plain posts stay open for discussion around the theses,
  revocable as today

# Order of work

1. TODO.md sandbox of `STATE.read` (defense-in-depth, and
   the same `load` shape both directories will use)
2. the genesis tree: `chains add --scripts`, clone brings it,
   `get metadata genesis` lists the two directories
3. the `ENV` and the `FMT` library: shared by both
4. contracts, local: run hook after `apply`/`recv`, `out/`
   layout, bound to REMOVAL/LIFT (with 260818-payloads.md
   S6.2); L1/L3 for plain posts (260903-128KB.md folded in)
5. validators, consensus: `keep` in `action.lua` (message
   shape, signing envelope, replay), the flag in `G.actions`,
   the revoke refusal, the instruction budget, the pinned VM
6. prototype UERJ on plain posts + contracts first; switch
   theses to `keep` once 5 lands

# Open

- `keep` message shape and how the tree is laid out (one
  file `p`? the 128 KB wrapper tree of 260903-128KB.md has
  the same shape `{ p = blob }`)
- the instruction budget value, and whether it is per chain
  (genesis) or a protocol constant
- how `apply` exposes metadata to a validator without
  exposing mutable `G`
- an on-DAG header (title, year) a validator could enforce,
  so an index survives even without a `keep`: public
  forever, metadata only; not before a case needs it
- `out/` across nodes: not synced; each peer regenerates
- do contracts see a `keep` refused by a validator? no: a
  refused post is not in the chain
