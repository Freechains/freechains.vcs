# 260819-git-state

- source: 260819-disk.md item 4 (the chosen successor)
- store per-commit state as GIT OBJECTS, not `.lua` files,
  so git's packfile delta+zlib collapses the O(N^2) pile
- RETIRES 260818-prune: no deletion, no P1/P2/P3

# Why

- snapshots are ~99% redundant (O(1) amortized real change
  per commit); git already delta-compresses near-identical
  blobs -> packed disk ~ O(N)
- validated need: chat sim was 15 GB of `.git/states` at
  6541 actions (see 260818-prune)
- `gc.auto` re-packs on its own during normal use, so the
  loose->packed cadence is automatic (no manual sweep for
  state; unlike prune)

# Storage model: blob + ref per commit

- for each freechains commit `cid`, store `serial(G)` as a
  git BLOB, pinned by `refs/states/<cid>` -> blob
    - a ref CAN point straight at a blob (git allows it)
    - refs make the blobs reachable -> gc keeps + packs them
- local-only: sync pushes/fetches `main` + `refs/begs/*` +
  `refs/payloads/*`, NEVER `refs/states/*` -> no wire cost
- O(N) local refs, absorbed by `packed-refs`

# STATE module rewrite (state.lua)

- `write(G, cid)`:
    - `blob = git hash-object -w --stdin` <- `serial(G)`
    - `git update-ref refs/states/<cid> <blob>`
- `read(cid)`: `load(git cat-file blob refs/states/<cid>)`
- `has(cid)`: `git show-ref --verify --quiet refs/states/<cid>`
- same call sites, same semantics; only the backing store
  moves from `.git/states/*.lua` to git objects

# Delta quality (MEASURE first)

- git delta is a HEURISTIC (window/depth), not guaranteed;
  our growing near-identical blobs are the ideal case
- STABLE serialize: sort keys so a reps change edits bytes
  in place, not shifts the whole file -> smaller deltas
- measure packed size on the chat sim vs the 15 GB baseline

# Read cost

- a read reconstructs the FULL blob (delta = disk win, not
  read-time win); a sync does only a HANDFUL of reads
- if the per-read `git cat-file` spawn hurts:
    - `git cat-file --batch`: many blobs, one process
    - flat cache for HEAD's state (the hot read)

# Packing cadence

- loose blobs are full-per-commit (O(N^2) transient) until
  packed -> rely on `gc.auto` (config, fires ~6700 loose)
- `sweep` still runs `git gc` (stage 1) as a manual nudge

# Steps

- S1: state.lua -> blob+ref backing (write/read/has)
- S2: stable serialize (sorted keys) in `serial`
- S3: ensure `gc.auto` sane on chain init (chains.lua)
- S4: measure on chat-02 sim: packed disk + read latency
- S5: confirm prune stays out (already reverted); update
  260818-prune as SUPERSEDED

# Open questions

- refs/states/* count: any tool that enumerates all refs?
  (for-each-ref cost, packed-refs size) -- measure
- does `abandon`'s reset leave orphan refs/states for
  dropped cids? cleanup on abandon, or let gc.auto handle
  (blob unreachable once ref deleted) -> delete the ref

# No back-compat

- new format only; do NOT import old `.git/states/*.lua`
  chains. Clean break, no migration path.
