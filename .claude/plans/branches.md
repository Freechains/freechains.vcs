# Branches

- the active branches, their git bases, and the features each holds
- the lineage: tree -> bug-winner -> sync-optim (1,2) -> tick -> backs
- goal: ia-optim holds the tree, the optimizations, and every
  feature of the other branches; then tick on top
- state (26/10/15): ia-optim holds everything, including the
  single 24h tick, the backs fix, git-batch, merge-cost, the
  canonical merge and the fetch-argmax fix; main, tick, backs and
  fetch-argmax carry the main-side forms; this file lives on main

# Active branches and deps

- main (55e9986, 26/10/15): plans only since 26/10/03 (this
  file, 261013-merge-cost, 261014-merge-order, 261015-fetch-argmax)
    - 261006-bug-winner: main@728f875 + the fix (2 commits)
    - 261008-tick (84e77d0, 26/10/09): main@7902953 + the tick
      rules (4 commits, under review)
        - e582932: half tick refunds, full tick rewards
        - 3027e34, 104e139, 84e77d0: single 24h tick replaces
          half/full; refund and reward at the same close;
          cli-revoke clawback; guide numbers (Alice 41500)
        - 261010-backs (fa4e701, 26/10/11): tick@84e77d0 +
          `backs` marks every visited commit, so a sync merge
          reached by many paths is walked once (b1b9cbc + plan:
          848 s of an 852 s usenet pull were inside `backs`)
    - 261015-fetch-argmax (c4defaa, 26/10/15): main@55e9986 + the
      payload fetch refspecs (glob + revoked excludes) through
      `git fetch --stdin` (temp file); `exec` raises "bug found"
      on a nil popen; `tst/bug-fetch-argmax.lua` (2400 revoked,
      22 min, commented out in the Makefile); under review: the
      plan still lists the main test run as pending
- 260914-tree-trash (a60fca6, 26/10/08): main@4d8e7d9 + the tree
  store + bug-winner (ported) + sync-optim fixes 1 and 2 + tick
  (ported to the tree, half/full form, stale)
    - 261007-ia-optim (41a90a6, 26/10/15): tree-trash@0483509 +
      28 process-floor fixes and 3 plan updates, then main merged
      (beg charge, discard --merge, docs, branches.md), tick
      cherry-picked from tree-trash@a60fca6, then the single tick
      cherry-picked from 261008-tick (3027e34..84e77d0; `close`
      keeps `STATE.fetch`, `bump`, `dirty`), backs re-applied
      (59566f4), then 261011-git-batch (031c070): `backs` by
      levels with one `cat-file --batch` per level, batched
      signer reads, memoized merge-base and ancestor; 175f19e:
      git-batch plan only
    - then 261013-merge-cost (5ebae95, 26/10/13), plan on main:
        - A: `--topo-order` on every range walk (merge dates 0
          broke `A..B`: wrong fork-winner signers, false voided)
        - B: `backs` from tips (in-process memo, snapshot
          `meta.lua`), no deep walk through merges
        - C: `tree_id` sort keys once, hex->bin memo; `put`
          reuses the tree id
        - D: one `rev-list` per com..tip (climb floor test and
          winner signers); winner peeks the floor's members
        - 41-commit pull at 8.8k: 456 -> 294 git processes,
          4.21 -> 3.00 s; 1 merge at 8k: 1.1 -> 0.65 s
    - then 261014-merge-order (3ad2442, 26/10/14), plan on main:
      sync joins both sides' tips in one sorted, dated-0 merge;
      merge state ranks parents by floor reps, then folds; voided
      tips dropped and refolded, "voided back" refusal; suites
      hardfork-merges, merge-paths; 48/48
        - the plan's status still says option 2 (post-only DAG)
          is to be tried; the commit is the canonical merge
          instead: plan to update
    - then 261015-fetch-argmax, tree form (ea396d4 + 41a90a6,
      26/10/15): one refspec per cid to fetch through `fetch
      --stdin`; `exec` nil-popen check; test (1200 posts, 3 min)
      commented out in the Makefile
    - 261014-ia-optim-merge (a7757d1): ia-optim@5ebae95 + the
      same canonical-merge commit as 3ad2442 (earlier copy, not
      an ancestor of ia-optim); superseded
- ia-optim holds every feature, but re-applied, not merged: none
  of tick@84e77d0, backs@fa4e701, fetch-argmax@c4defaa,
  main@55e9986 is its ancestor
    - a `git merge` of those branches would conflict on the same
      changes: keep cherry-picking from them
    - missing from ia-optim: this file (main form), the plans
      261010-backs, 261013-merge-cost, 261014-merge-order,
      261015-fetch-argmax (code is in)
- installed build: ia-optim@5ebae95 (26/10/13 22:18); its clone
  of a 5k-post chain fails (the argmax bug)
- tests on ia-optim: the hook suites need the working tree first
  in PATH (or `make install`): an older installed build writes
  snapshots without `tick`
- guide.sh (both forms, 26/10/09): reps match the single tick;
  the daemon "Address already in use" lines come from the extra
  `--listen=127.0.0.1` (daemon.lua already binds 0.0.0.0); comment
  at ln 142 still says 40000
- pending: paper items of 261008-tick; tree-trash not updated to
  the single tick (superseded by ia-optim); main run of
  bug-fetch-argmax (22 min); install 41a90a6, rerun 2606-sims
  full usenet (stopped at 8.8k on 175f19e; clone at 5k on
  5ebae95); clone cost vs size (14 s at 1k, > 75 s at 5k)

# Flow of the latest features

| plan             | branches               | description                |
|------------------|------------------------|----------------------------|
| 261015-fetch-    | fetch-argmax (main     | payload fetch refspecs via |
| argmax           | form); ia-optim (tree  | `fetch --stdin`, past the  |
|                  | form); main (plan)     | 128 KB `sh -c` cap; `exec` |
|                  |                        | raises on a nil popen      |
| 261014-merge-    | ia-optim (canonical    | same posts, other merges:  |
| order            | merge + tests); main   | hard fork; fix: one sorted |
|                  | (plan, says option 2)  | merge of both tip sets     |
| 261013-merge-    | ia-optim (code);       | A: --topo-order ranges     |
| cost             | main (plan)            | B: backs from known tips   |
|                  |                        | C: cheaper tree_id/put     |
|                  |                        | D: one range per com..tip, |
|                  |                        | winner peeks members;      |
|                  |                        | big pulls -30%, 1 merge    |
|                  |                        | at 8k 1.1 -> 0.65 s        |
| 261011-git-batch | ia-optim               | recv on merge-heavy DAGs:  |
|                  |                        | backs by levels, batched   |
|                  |                        | signer reads, memoized     |
|                  |                        | merge-base; git reads on a |
|                  |                        | merge pull 220 -> 39       |
| 261010-backs     | backs (fix + plan);    | backs walks each merge     |
|                  | ia-optim (code only)   | once: no exponential walk  |
| 261008-tick      | tick, backs (main      | one chain clock replaces   |
| (single 24h)     | form); ia-optim (tree  | the 12h/24h per-post timers|
|                  | form); tree-trash      | refund and reward at the   |
|                  | (half/full, stale)     | same close                 |
| 261007-sync-optim| tree-trash, ia-optim   | recv flat in chain size:   |
|                  |                        | hardfork from tips, payload|
|                  |                        | pass on the affected set   |
| (process floor)  | ia-optim               | post 71 -> 13 procs, recv  |
|                  |                        | 224 -> 39, clone 689 -> 219|
| 261006-bug-winner| bug-winner (fix);      | fork winner independent of |
|                  | tree-trash, ia-optim   | the replay path; snapshots |
|                  | (ported); main, tick,  | from the DAG only          |
|                  | backs, fetch-argmax    |                            |
|                  | (plan only)            |                            |
| 261005-races     | main, bug-winner, tick,| concurrent commands on one |
|                  | backs, fetch-argmax    | chain (writer vs readers)  |
|                  | (plan only)            |                            |
| 261005-hook-url  | main, bug-winner, tick,| hub hook url injection and |
|                  | backs, fetch-argmax    | unquoted URL() splices     |
|                  | (plan only)            |                            |
| 261002-docs      | main, bug-winner, tick,| guide/reps synced with the |
|                  | backs, fetch-argmax    | paper, figures             |
|                  | (done)                 |                            |
| 260923-beg       | all (done)             | begs charged on admission  |
|                  |                        | (rule 2)                   |
| 260921-discard   | all but tree-trash     | discard --merge drops a    |
|                  |                        | branch from its first      |
|                  |                        | action                     |
| 260914-tree      | tree-trash, ia-optim   | state as a git tree of     |
|                  |                        | per-entity files, lazy     |
| 260903-128KB     | all (plan only)        | payload size limit, local  |
| 260829-otim      | all (plan only)        | per-action state cost;     |
|                  |                        | superseded by 260914-tree  |
