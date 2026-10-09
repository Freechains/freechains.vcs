# Branches

- the active branches, their git bases, and the features each holds
- the lineage: tree -> bug-winner -> sync-optim (1,2) -> tick
- goal: ia-optim holds the tree, the optimizations, and every
  feature of the other branches; then tick on top

# Active branches and deps

- main (6996cc3, 26/10/08): plans only since 26/10/03
    - 261006-bug-winner: main@728f875 + the fix (2 commits)
    - 261008-tick: main@7902953 + the tick rules (origin only,
      1 commit, unreviewed)
- 260914-tree-trash (a60fca6, 26/10/08): main@4d8e7d9 + the tree
  store + bug-winner (ported) + sync-optim fixes 1 and 2 + tick
  (ported to the tree, unreviewed)
    - 261007-ia-optim: tree-trash@0483509 + 28 process-floor fixes
      and 3 plan updates, then main merged (beg charge, discard
      --merge, docs, branches.md) and tick cherry-picked from
      tree-trash@a60fca6: holds everything (26/10/08)
- tests on ia-optim: the hook suites need the working tree first
  in PATH (or `make install`): the installed build writes
  snapshots without `tick`

# Flow of the latest features

| plan             | branches               | description                |
|------------------|------------------------|----------------------------|
| 261008-tick      | tick (main form);      | one chain clock replaces   |
|                  | tree-trash, ia-optim   | the 12h/24h per-post timers|
|                  | (tree form)            |                            |
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
