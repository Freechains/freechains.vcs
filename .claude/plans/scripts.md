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

- dies: any consensus decision over a payload that can be
  ERASED, and any global state machine over such payloads
  (balances, counters): two peers never agree once one is gone
- dies: a decision that reads OTHER posts' payloads: a later
  revoke flips the result, peers diverge
- splits: the first draft's single "script" becomes two kinds
  of code with two trust levels
    - a CONTRACT builds things from content: local, free,
      best-effort; wrong on one machine hurts one machine
    - a VALIDATOR decides about the post in consensus: whether
      it may be revoked, what it costs, who it pays; it is
      deterministic by construction and budgeted, and it may
      only decide over bytes that are IN the DAG
- the one rule behind everything: A PAYLOAD THE CONSENSUS
  DEPENDS ON CANNOT BE ERASED; so a non-trivial validator
  answer moves the payload into the DAG, and a payload left
  off the DAG can carry no consensus effect

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

# Validators: consensus scripts

## Signature: a list of commands

```lua
-- validators/<name>.lua
return function (act, pay, G)
    -- act: { action, member, time, backs, cid }  immutable
    -- pay: the payload bytes (nil for a payload-less action)
    -- G:   the chain state at apply, READ-ONLY (deterministic
    --      at replay, so reading it is fine; writing goes
    --      through the returned commands only)
    return {
        { "like",    n=500,   cid=act.cid,   as=<pub> },
        { "dislike", n=1000,  member=<pub>,  as=act.member },
        { "revoke",  n=-1000, cid=<cid>,     as=<pub> },
        { "lock" },   -- this post is irrevocable (see below)
    }
end
```

- the answer is a LIST OF COMMANDS, the same vocabulary as
  the CLI: `like`, `dislike`, `revoke`, `unrevoke`, plus
  `lock` (name open), which exists only here
- `as` is any member key: the command is issued AS that
  member, UNSIGNED; there is no key to verify, the genesis
  vouches for the script and the script vouches for the
  command
- shorthands: `{}`, `nil` or `true` is the TRIVIAL answer (a
  plain post, as today); `false` or an error REFUSES the post
- a non-empty list is a consensus effect, so the payload
  must ride in the DAG (below), and an in-DAG post is
  irrevocable by construction: `lock` is the command for a
  validator that wants ONLY that
- which validators run: all of them, in sorted file order, or
  one named by the post (`post <name> ; ...`); open; sorted
  order needs no message change

## Commands: virtual actions through the same `apply`

- a command is a VIRTUAL action: no commit, no cid, no
  signature; it is re-derived by every replay from the real
  post that triggered it, so it never needs to travel
- it runs through `RULES.apply` with `env.sign = as`, the
  trigger's `time` and `backs`, right after the trigger's own
  mutation; so EVERY rule of the economy holds unchanged
    - `as` pays: `like`/`dislike` cost `|n|`, `revoke` costs
      at least `C.reps.revoke`, tax `C.vote.tax`, split
      `C.vote.split`, cap `C.reps.max`
    - `insufficient reputation` on any command REFUSES the
      whole post: atomic, and the poster's client saw it first
    - `as` may be a non-member: `bump` creates members, and
      the gates then decide as for anyone
- so a validator redistributes reps, it never mints them: a
  posting fee is a `dislike` as the poster, a reviewer's
  credit is a `like` as the poster on the reviewer, moderation
  by code is a `revoke` as the chain's key
- no `post` command: a virtual post has no payload; not
  before a case needs it
- commands never trigger validators: only REAL posts do, so
  there is no recursion
- `as` anyone is real power: a genesis can drain its members
  by script; joining a chain is accepting its validators, as
  it already is accepting its dictators; the tree is under the
  genesis hash, visible before `chains add clone` (a
  `--scripts` listing there, as a package manager shows a
  post-install script)

## Where the payload lives follows the answer

- the poster's client runs the validators before committing
    - trivial: `post ; <blob>`, empty tree, anchored at
      `refs/payloads/<cid>`, revocable, as today
    - non-trivial: the SAME message, but the commit TREE holds
      the blob; the bytes travel with the commit, forever
    - refused: nothing is committed
- `apply` on every peer
    - non-empty tree: run the validators over the tree's
      bytes; the answer must be non-trivial and its commands
      are applied; a trivial or refused answer is `malformed
      commit`; the check at `action.lua:277` ("unexpected
      tree") is the one line that relaxes, and its comment
      names the price: relayed forever, un-revocable
    - empty tree: the validators do NOT run in `apply` (no
      bytes at replay); the post is trivial by construction
    - `revoke` on an in-DAG entry: refused from the placement
      alone (a flag set at apply), one line beside `"invalid
      target : expects 'action'"`; no bytes needed at revoke
      time; self-revoke refused too, the in-DAG placement IS
      the author's consent, the genesis tree IS the chain's;
      a virtual `revoke` is refused the same way
    - dislikes unaffected (they hit the author, not the
      content)
- running once at the post and re-deriving the commands at
  replay equals running at every revoke: both inputs are
  immutable
- the off-DAG dodge: a client that keeps the tree empty to
  skip a fee
    - peers run the validators at L3 when the bytes arrive:
      a non-trivial answer over an off-DAG payload means the
      poster dodged; drop the anchor, never host the bytes
    - the post stays in the DAG, paid `C.reps.cost`, earns
      1.b, and is REVOCABLE: nothing the community cannot
      undo with today's tools; the dodger served no content
    - so the mixed chain (some posts in the DAG, most off it)
      holds without a chain-wide mode
- plain `post ; <blob>` never meets a validator in `apply`:
  its bytes are off the DAG and revocable

## What a validator must be, as consensus code

- deterministic BY CONSTRUCTION, not by good will: the `ENV`
  it loads with offers only pure primitives; no `os`, `io`,
  `math.random`, no clock, no `require`
- no `pairs`: Lua 5.4 seeds string hashing per process, so
  table order differs between peers; the API gives sorted
  iteration only (`serial(G)` already sorts for the same
  reason); `G` is exposed through such accessors
- an INSTRUCTION budget, not a time budget:
  `debug.sethook(f, "", N)` counts VM instructions, the same
  on every peer running the same Lua; over budget is a
  refusal, deterministically; a wall clock would fork peers
- the Lua version pinned: instruction counts and stdlib
  behavior are per version; genesis line 1 already carries a
  version, it must cover the VM too
- input is the action, its own payload, and read-only `G`;
  never other payloads (erasable)
- a buggy validator forks or bricks ONE chain, whose creator
  already is its trust root (pioneers, dictators);
  acceptable, as a bad genesis is
- validators are genesis-only; a user-posted validator would
  be consensus code nobody agreed to
- declarative checks (MIME, magic bytes, size, fields) are a
  LIBRARY the validators call (`FMT.mime`, `FMT.size`), not
  a separate mechanism
- 128 KB is a HARD rule for an in-DAG payload: every peer
  carries it forever; `apply` refuses above `C.post.size`
  (the 128 KB plan's "replay never sees the bytes" premise
  no longer holds for these; its L1/L3 stay for the rest)

## Costs, to be accepted with open eyes

- no right to be forgotten for an in-DAG post: the free
  self-revoke in `rules.lua` exists for exactly that
- illegal content that passes a validator is permanent; only
  dislike or leaving the chain remain; fine for an
  institutional repository, not for open chains
- every peer carries every in-DAG payload forever: disk,
  clone bandwidth
- `action.lua:277` stops being an invariant: "no bytes on the
  DAG" becomes "no bytes on the DAG unless a validator
  vouched for them"

# Contracts: side effects, local

- run on every ACCEPTED post, in-DAG or plain, after `apply`
  on the poster's node and on `recv` on every other; never
  inside `apply`, never a verdict, never reps
- output under `chains/<name>/out/<cid>/`, plus aggregates
  regenerated from the survivors
- input: the post's payload (`nil` when revoked or missing,
  as `get` refuses it), its metadata, the DAG, and `G`
    - over an in-DAG post the input is the same on every
      peer, so the site is the same everywhere
    - over a plain post it is best-effort, as before
- `out/` follows the anchor crossings of plain posts
    - REMOVAL (entered revoked): delete `out/<cid>/`
    - LIFT (bytes back via `--file` or sync): regenerate
    - 260818-payloads.md S6.2 (`apply` emits anchor events)
      is the natural hook: one path for `like` and `sync`
    - an in-DAG post never crosses: its products stay
- also usable as LOCAL validation of plain posts: L1 in
  `post` refuses to publish, L3 in `recv` drops the anchor
  and never hosts the bytes; "reject the block" becomes
  "reject the bytes"; with the withholding tracker a post
  every peer rejects is invisible in practice
- a contract may execute ANY command: shell, tools, the
  freechains CLI itself (a real, signed `like` from the local
  key is the local counterpart of a validator's virtual one)
    - that is arbitrary code from a remote genesis on the
      cloning machine (T6c), so contracts run only after an
      explicit local OPT-IN per chain (`freechains.contracts`
      in the repo config, default off), as one reads a
      package's post-install script before enabling it
    - a user-submitted contract is opted in by the like that
      consents to it
- a local contract that fails determinism yields a wrong
  site on one machine, nothing more: no budget, no
  determinism rule, no sandbox beyond the opt-in
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
  `FMT.size`; returns `{ {"lock"} }` for a thesis, so it
  rides in the DAG: permanent, reproducible, the repository
  the department wants; `false` for anything else by a
  student key, `{}` (plain, revocable) for staff notes
- optional: `{ "like", n=500, member=advisor, as=act.member }`
  with the advisor read from the PDF metadata: the student
  pays, the advisor is credited, under the like rules
- `contracts/site.lua`: thesis -> `out/<cid>/index.html`,
  plus a regenerated index; local, same on every peer since
  every thesis is in the DAG
- plain posts stay open for discussion around the theses,
  revocable as today

# Order of work

1. TODO.md sandbox of `STATE.read` (defense-in-depth, and
   the same `load` shape both directories will use)
2. the genesis tree: `chains add --scripts`, clone brings it,
   `get metadata genesis` lists the two directories
3. the `ENV`, the sorted `G` accessors and the `FMT` library:
   shared by both
4. contracts, local: run hook after `apply`/`recv`, `out/`
   layout, bound to REMOVAL/LIFT (with 260818-payloads.md
   S6.2); L1/L3 for plain posts (260903-128KB.md folded in)
5. validators, consensus: relax `action.lua:277` for a
   vouched tree, run in `apply` (post path, after gating,
   after the post's mutation), the in-DAG flag in
   `G.actions`, virtual commands through `RULES.apply` with
   `env.sign = as`, the revoke refusal, the instruction
   budget, the pinned VM, the L3 dodge check
6. prototype UERJ on plain posts + contracts first; switch
   theses to validators once 5 lands

# Open

- tree layout for an in-DAG payload: one entry `p` (the same
  shape as the 128 KB wrapper tree `{ p = blob }`)
- all validators in sorted order, or one named in the
  message? sorted needs no message change; named lets a
  chain hold several content types cheaply
- the instruction budget value, and whether it is per chain
  (genesis) or a protocol constant
- the `G` accessor surface: members, actions, order; enough
  for fees and rewards, nothing that leaks `pairs` order
- do validators also see `like`/`revoke` actions (their
  `why`)? not before a case needs it
- gating rule 1.b (no daily award for a post) has no command:
  a virtual self-revoke would erase, and in-DAG cannot; add a
  command only if a case needs it
- `as` a non-member with no reps in a gated chain: the
  command fails and refuses the post; is that the right
  default, or should validators only speak as members?
- a virtual `like` as the poster on the poster's own post:
  today's rules on self-votes apply unchanged, check them
- an on-DAG header (title, year) a validator could enforce,
  so an index survives even without an in-DAG body: public
  forever, metadata only; not before a case needs it
- `out/` across nodes: not synced; each peer regenerates
- `discard` and prune (prune.md) over in-DAG payloads: a
  flattened history must keep the vouched trees
