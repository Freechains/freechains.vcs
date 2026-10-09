# Branches

- the active branches, their git bases, and the features each holds
- the lineage: tree -> bug-winner -> sync-optim (1,2) -> tick
- goal: ia-optim holds the tree, the optimizations, and every
  feature of the other branches; then tick on top

# Active branches and deps

- main (7902953, 26/10/08): plans only since 26/10/03
    - 261006-bug-winner: main@728f875 + the fix (2 commits)
    - 261008-tick: main@7902953 + the tick rules (origin only,
      1 commit, unreviewed)
- 260914-tree-trash (0483509, 26/10/07): main@4d8e7d9 + the tree
  store + bug-winner (ported) + sync-optim fixes 1 and 2
    - 261007-ia-optim: tree-trash@0483509 + 28 process-floor fixes
      and 3 plan updates (31 commits)
- not on tree-trash/ia-optim (main after 4d8e7d9): beg charge,
  discard --merge, docs sync; to port
- next in the lineage: tick onto ia-optim

# Flow of the latest features

| plan             | branches               | description                |
|------------------|------------------------|----------------------------|
| 261008-tick      | tick                   | one chain clock replaces   |
|                  |                        | the 12h/24h per-post timers|
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
| 260923-beg       | main, bug-winner, tick | begs charged on admission  |
|                  | (done); tree-trash,    | (rule 2)                   |
|                  | ia-optim (not ported)  |                            |
| 260921-discard   | main, bug-winner, tick | discard --merge drops a    |
|                  | (code); tree-trash,    | branch from its first      |
|                  | ia-optim (not ported)  | action                     |
| 260914-tree      | tree-trash, ia-optim   | state as a git tree of     |
|                  |                        | per-entity files, lazy     |
| 260903-128KB     | all (plan only)        | payload size limit, local  |
| 260829-otim      | all (plan only)        | per-action state cost;     |
|                  |                        | superseded by 260914-tree  |
