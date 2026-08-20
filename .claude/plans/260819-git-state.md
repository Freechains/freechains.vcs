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

- S1 DONE (26/08/19): state.lua -> blob+ref backing
    - write: hash-object -w (via .git/state-tmp) + update-ref
    - read: cat-file blob; has: show-ref --verify --quiet
    - chains.lua genesis(): writes the blob too; dropped the
      `mkdir .git/states/`
    - tst/tests.lua STATE() helper reads the blob
    - full suite green (installed freechains is STALE, so the
      pre-receive hook needs a real `make install`; validated
      here with a PATH shim to the worktree)
- S2 DONE (26/08/19): already satisfied -- `serial`
  (common.lua:56) sorts keys at every level, so output is
  deterministic and stable (reps change = in-place edit).
  No code change.
    - S4 to weigh: actions sort by AID (hash) -> a new one
      inserts mid-file; serializing by `G.order` instead
      would be pure-APPEND -> tighter deltas. Optional.
- S3 DONE (26/08/19): `git config gc.auto 256` in git_init
    - one large loose blob per action; default 6700 would let
      the loose pile balloon (O(N) each). 256 packs often,
      backgrounded (autoDetach), fired by `commit`'s gc --auto
    - verified: refs/states/* are `blob` refs keyed by cid;
      state reads/writes work; value to be tuned in S4
- S4 DISK DONE (26/08/19): chat sim, 9580 msgs / 6541
  actions (reinstalled with gc.auto 256 midway):
    - file-based baseline .......... 15.3 GB (states)
    - prune + manual sweep ......... 1.5 GB
    - git-state, mid-run (loose) ... 507 MB (no sweep)
    - git-state, PACKED FLOOR ...... 28.56 MiB (git gc)
      - loose 0, one pack, 35378/66586 delta'd (~53%)
      - ~535x vs baseline, ~50x vs prune: the O(N) delta
        chain, on real data, automatic
      - whole chain dir `du -sh` = 66 MB (28.6 MB `.git` +
        ~37 MB working tree of 6541 action files -- the
        irreducible content)
      - the 507 MB mid-run was almost all LOOSE state blobs;
        gc.auto 256 from the START bounds that tail and holds
        disk near this floor with no manual step
    - the sim's disk() helper now reports pack vs loose (was
      reading the empty `.git/states/`)
    - S4 leftovers (optional): read latency (cat-file vs file
      read); transient with gc.auto 256 from the start;
      aid-hash vs G.order ordering (may shrink the floor)

# Conclusion (26/08/19)

- item 4 VALIDATED: automatic git packing makes state disk
  ~28 MB at 6541 actions, no sweep, no prune. Beats prune by
  ~50x and needs no manual step. Prune stays retired.
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
