# 280808-redesign

- sources: `trash/b803-260802-redesign.md`, `trash/b807-260807-redesign.md`

# Done (already on main)

- `chain/consensus.lua` extracted from sync.lua
    - `octopus`, `consensus`, `commit`, `replay` (climb/meet)
- FF special-casing removed from recv
    - unified into diverge path
    - post-replay hardfork check
    - state probe after final ref update
- snap writes landed then REVERTED (563a745)
    - only `git_config` -> `git_init` refactor kept
- `tmp/` -> `.git/` (allowed_signers scratch)
- fixes: clone drops pending begs, clock skew (pinned `GIT_*_DATE`)
- `tst/trash/bug-forged-state.lua`: 4 holes proven red, parked
- NOT present: snapshots, backfill, `.git/index.lua`,
  `actions/<aid>.lua`; trailers + 4-file `state/` tree still live

# Ladder (local-only; all local tests pass after each step)

- state `G` = `{ authors, posts, order, now }` (4 facets)
    - snapshot = `serial(G)` in `.git/states/<cid>.lua`
- L1: snaps after local actions — dual write
    - genesis (`chains add`), post, like (beg: before reset)
- L2: local reads of snaps
    - `PEAK`, init.lua startup `G`, destroy restore,
      like-on-beg entry
    - miss -> lazy fallback: read tree state, snap it
- L3: remove state commits + tree state from local writers
    - possible w/o aid redesign: snapshot written AFTER commit,
      cid known -> no cycle
    - one commit per action; beg 2 -> 1; destroy `beg~2` -> `beg~1`
    - like beg merge: pure topology, no `-X ours` on state
    - local tests updated to new anatomy
    - sync recv/mode-check unchanged -> sync tests fail, accepted
- dropped: backfill walk (only needed for commits we did not
  create: sync interiors, clone) — deferred to sync phase

# What leaves commits

- state (`state.lua` / `state/`): no longer committed at all (S15)
- state commits themselves: action + state join into one commit (S9)
- payloads (post content, like `--why`): out of the tree (S10)
- trailers (`Freechains:` kind): classification derived from tree (S11a)
- commit messages: empty placeholder, no user text
- `.freechains/` prefix, `.gitattributes`, `.gitignore`, skel

# What enters commits

- one `actions/<aid>.lua` per action:
    - `{action, backs (aids), sign, time, blob, post/author, n}`
- tree = `actions/` (sharded `ab/`) + `genesis.lua` + `random`
- merges: pure topology, empty diff
- genesis: no actions

# What enters local state

- per-commit snapshots of whole `G` -> `.git/states/<cid>.lua`
    - written at tips + replay
    - backfill walk fills interiors, clone, old chains
- commit<->aid index -> `.git/index.lua` (`{tip, a2c, c2a}`)
- payload blobs anchored by `refs/payloads/<aid>` (never in tree)
- `allowed_signers` scratch -> `.git/`

# What leaves local state

- remote/committed state: never read again
    - `G_oct`, `PEAK`, worktree `dofile`, destroy, like-on-beg
      all switch to snapshots
- verification machinery never built:
    - no `state_link`, no verify walk
    - no `refs/freechains/verified` frontier
    - no write+diff probe
- GC: snapshots below the settled hardfork window die (S15.3)
- prune:
    - below-cut snapshots die
    - prune-point snapshot rekeyed to the new orphan root
    - `.git/index.lua` deleted, rebuilt lazily
- worktree `tmp/` gone (moved into `.git/`)
