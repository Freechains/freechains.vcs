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
- S3 REVERTED (26/08/20): tried `gc.auto 256`, then removed
  it. The S4 second run proved auto-gc can't hold the floor
  (2.4 GB loose tail) and only adds churn -> rely on sweep's
  explicit gc instead. `git_init` sets no gc.auto.
- CLEANUP (26/08/20): abandon deletes `refs/states/<cid>`
  for dropped commits (symmetric with refs/payloads), so gc
  can reclaim orphaned state blobs. sweep.lua doc now names
  the state-pack role of its `git gc`.
    - NOTE: the old file-based abandon leaked too (orphan
      `.lua` files, never cleaned) -- this is a latent leak
      now fixed, not a regression
    - test in cli-abandon.lua: after abandon, p2's state ref
      is gone, p1's remains, and `gc --prune=now` reaps the
      orphaned blob (reflog does not pin it: state blobs live
      outside commit trees)
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

# S4 SECOND RUN (26/08/20): gc.auto 256 from the START

- fresh install, gc.auto 256 all along, full 9580-msg run:
    - END: git 2249 MB (pack 10.3, LOOSE 2398.9) -- a 2.4 GB
      loose tail; auto-gc did NOT hold the floor
    - runtime 53 min vs 48 min file-based (same chat sim) =
      ~+10%: the extra hash-object + update-ref per action,
      NOT a doubling (my earlier "2x" mis-compared to grow.sh)
- WHY auto-gc fails to maintain it:
    - each `gc --auto` is O(N); git's gc lock SKIPS a trigger
      while one is running -> past some N, triggers are
      always skipped and loose grows unbounded
    - gc.auto 256 may be COUNTERPRODUCTIVE: so frequent the
      gc's never finish. A bigger threshold, or auto off +
      explicit gc, may pack MORE
- the floor is only reached by an EXPLICIT `git gc`:
    - this from-start run: `git gc` -> 32.2 MiB, loose 0
      (2.4 GB tail fully reclaimed; ~matches the 28.6 earlier,
      variance = delta selection). Floor is ~30 MB either way.
    - so the tail is purely TRANSIENT; one gc always recovers

# S4 THIRD RUN (26/08/20): BARE repos (branch 9a9593d)

- same sim, bare chain (no worktree), no gc.auto: 57 min,
  end 2.4 GB loose (pack 0 -- no auto gc, as designed)
- after explicit `git gc`: size-pack 46.2 MiB, du 58 MB
    - vs worktree run: 70 MB total -> 58 MB (the ~38 MB
      worktree copy is gone)
    - BUT pack grew 32.2 -> 46.2 MiB: `repack.writeBitmaps`
      defaults ON in BARE repos -- bitmap file + bitmap
      ordering constrains delta selection (29288 deltas vs
      32618). Bitmaps only speed fetch-serving counting.
    - bitmaps were NOT the cause: disabling saved ~0.5 MiB
      (45.7). Real cause: single-shot gc (reused 0) finds
      worse deltas than the old incremental gc.auto packs
    - FIX (measured): `repack -adf --window=50` -> 23.14 MiB,
      the best floor of all runs -> `pack.window 50` in
      git_init; sweep's gc is rare, extra CPU fine
- runtimes creeping: 48 (files) / 53 (git-state) / 57 min
  (bare); plumbing-per-action cost, watch if it grows

# S4 FINAL STUDY (26/08/21): config matrix + bare verdict

- pack config matrix (repack -adf on the saved 10k chain,
  66586 objects; time ~flat 150-270s, uncorrelated):

| window | depth | pack     |
|--------|-------|----------|
| 10     | 50    | 45.9 MB  |
| 20     | 50    | 37.0 MB  |
| 50     | 50    | 24.5 MB  |  <- knee; CHOSEN
| 100    | 50    | 23.7 MB  |  (+3%: not substantial)
| 250    | 250   | 23.7 MB  |
| 50     | 10    | 25.7 MB  |
| 50     | 100   | 23.7 MB  |

- bitmaps ISOLATED (window 50, on vs off): pack IDENTICAL
  (23699K); the bitmap is a 0.7 MB sidecar. The earlier
  46-vs-32 attribution to bitmaps was WRONG (it was the
  window/reuse story) -> `writeBitmaps false` DROPPED from
  git_init (simplicity; nothing measurable)
- bare vs non-bare (chat-02 N=1000 ~ 650 actions, same
  code era, same config, both gc'd):

|          | run  | pack    | worktree | total  |
|----------|------|---------|----------|--------|
| bare     | 165s | 1.40 MB | --       | 2.7 MB |
| non-bare | 140s | 1.36 MB | 4.1 MB   | 6.8 MB |

- packs identical; the whole gap is the worktree (~6 KB per
  action) -> non-bare total 2.5x bigger; bare posts +18%
- VERDICT (goal = disk): keep BARE + pack.window 50, depth
  default, no bitmap config. Total at 6.5k actions ~33 MB
  (23.7 pack + ~9 refs/index) vs 15.3 GB baseline: ~460x

## big picture (6541-action wikimedia chain)

| arrangement                        | total     |
|------------------------------------|-----------|
| file snapshots                     | 15,300 MB |
| prune (keep 500) + sweep           |  1,500 MB |
| git-state, default pack, worktree  |     70 MB |
| git-state + window 50, worktree    |    ~57 MB |
| git-state + window 50 + BARE       |    ~33 MB |

- levers in order: git-state (structural, O(N^2)->O(N)),
  pack.window 50 (one line), bare (kills the worktree copy)
- costs: ~+10% post (git-state), +18% post (bare), one
  explicit `git gc` (sweep) to reach the floor

# Conclusion (26/08/20) -- REVISED

- item 4 wins on DISK FLOOR: 28.6 MB vs prune's 1.5 GB, and
  no P1/P2/P3 logic -- but NOT zero-maintenance:
    - needs an explicit `git gc` (sweep keeps stage-1 gc);
      auto-gc alone leaves a multi-GB loose tail
    - write latency ~+10% (two extra git spawns per action;
      53 vs 48 min on the chat sim) -- modest
- still simpler than prune (sweep = just `git gc`, no
  boundary/delete logic) and prune stays retired
- OPEN before shipping:
    - tune/settle packing: gc.auto value, or auto off +
      sweep-driven gc; measure loose tail vs threshold
    - write latency: batch hash-object/update-ref? keep a
      flat HEAD cache and only blob older states?
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
