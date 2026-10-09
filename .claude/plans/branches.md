# Branches

- the active branches, their git bases, and the features each holds
- the lineage: tree -> bug-winner -> sync-optim (1,2) -> tick
- goal: ia-optim holds the tree, the optimizations, and every
  feature of the other branches; then tick on top
- state (26/10/09): ia-optim holds everything, including the
  single 24h tick; main and tick carry the main-side forms

# Active branches and deps

- main (6996cc3, 26/10/08): plans only since 26/10/03
    - 261006-bug-winner: main@728f875 + the fix (2 commits)
    - 261008-tick (84e77d0, 26/10/09): main@7902953 + the tick
      rules (4 commits, under review)
        - e582932: half tick refunds, full tick rewards
        - 3027e34, 104e139, 84e77d0: single 24h tick replaces
          half/full; refund and reward at the same close;
          cli-revoke clawback; guide numbers (Alice 41500)
- 260914-tree-trash (a60fca6, 26/10/08): main@4d8e7d9 + the tree
  store + bug-winner (ported) + sync-optim fixes 1 and 2 + tick
  (ported to the tree, half/full form, stale)
    - 261007-ia-optim (d995b64, 26/10/09): tree-trash@0483509 +
      28 process-floor fixes and 3 plan updates, then main merged
      (beg charge, discard --merge, docs, branches.md), tick
      cherry-picked from tree-trash@a60fca6, then the single tick
      cherry-picked from 261008-tick (3027e34..84e77d0; `close`
      keeps `STATE.fetch`, `bump`, `dirty`): holds everything
- tests on ia-optim: the hook suites need the working tree first
  in PATH (or `make install`): the installed build writes
  snapshots without `tick`
- guide.sh (both forms, 26/10/09): reps match the single tick;
  the daemon "Address already in use" lines come from the extra
  `--listen=127.0.0.1` (daemon.lua already binds 0.0.0.0); comment
  at ln 142 still says 40000
- pending: paper items of 261008-tick; tree-trash not updated to
  the single tick (superseded by ia-optim)

# Flow of the latest features

| plan             | branches               | description                |
|------------------|------------------------|----------------------------|
| 261008-tick      | tick (main form);      | one chain clock replaces   |
| (single 24h)     | ia-optim (tree form);  | the 12h/24h per-post timers|
|                  | tree-trash (half/full, | refund and reward at the   |
|                  | stale)                 | same close                 |
| 261007-sync-optim| tree-trash, ia-optim   | recv flat in chain size:   |
|                  |                        | hardfork from tips, payload|
|                  |                        | pass on the affected set   |
| (process floor)  | ia-optim               | post 71 -> 13 procs, recv  |
|                  |                        | 224 -> 39, clone 689 -> 219|
| 261006-bug-winner| bug-winner (fix);      | fork winner independent of |
|                  | tree-trash, ia-optim   | the replay path; snapshots |
|                  | (ported); main, tick   | from the DAG only          |
|                  | (plan only)            |                            |
| 261005-races     | main, bug-winner, tick | concurrent commands on one |
|                  | (plan only)            | chain (writer vs readers)  |
| 261005-hook-url  | main, bug-winner, tick | hub hook url injection and |
|                  | (plan only)            | unquoted URL() splices     |
| 261002-docs      | main, bug-winner, tick | guide/reps synced with the |
|                  | (done)                 | paper, figures             |
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
