# Goal

- fewer git processes per `sync recv` on merge-heavy DAGs
- one batched read instead of one `cat-file` per commit
- memoize ancestry queries within one process
- same results: HEAD, `list order`, refs, reps

# Evidence (26/10/11, ia-optim 59566f4 installed)

- found by 2606-sims usenet local first
    - mids sync every 6 h, leaves every 24 h
    - ~1.3 merges per post; 80% forks at 1,500 actions
    - `/x/papers/2606-sims/.claude/plans/260924-topology.md`
- copies of live peers at ~1,885 actions, `--now` pinned
    - ff pull (5 new actions): 1.08 s, ~65% in git calls
    - merge pull (19 new actions): 2.13 s, ~60% in git calls
- git calls per pull (ff / merge), by caller:
    - 113 / 113 `cat-file commit`:
      `M.backs` -> `M.is` -> `GIT.cat` (action.lua:199)
    - 28 / 33 `cat-file commit`:
      `collect_keys` -> `SSH.signer` (consensus.lua:152)
    - 7 / 28 `log --reverse`: `collect_keys` (consensus.lua:148)
    - 7 / 31 `merge-base --is-ancestor`: `ancestor`
      (consensus.lua:274), from `climb` / `meet`
    - 2 / 10 `merge-base`: `M.winner` (consensus.lua:113)
- each process ~2.5 ms (`cat-file`) to ~13 ms (`merge-base`)
- git work itself is small: the cost is process start-up

# Fix 1: `backs` walks level by level

- BFS over the frontier instead of recursion
- `GIT.cats(frontier)` once per level, then `M.is`, parents
- cost: one `cat-file --batch` per DAG level, not per commit
- result unchanged: same set, sorted

# Fix 2: batch the signer reads in `collect_keys`

- collect the `log --reverse` cids first
- `GIT.cats(cids)` once, then `SSH.signer` per cid
- `SSH.signer` already reads through `GIT.cat` (memo) in
  chain context: nothing to change

# Fix 3: memoize ancestry per process

- `ancestor(a, b)`: table keyed "a b" (immutable fact)
- `M.winner` merge-base: table keyed "a b"
- `collect_keys`: memo per "com..tip" range

# Maybe: one long-lived `cat-file --batch`

- Lua `io.popen` is one-way: needs luaposix pipes
- only if fixes 1-3 leave git calls dominant

# Check

- sims: same pair, same `--now`, before and after
    - git calls per pull, time per pull
    - same HEAD, `list order`, refs, reps
- rerun usenet local first in 2606-sims

# Status

- [x] plan
- [x] fix 1: `backs` by levels
- [x] fix 2: batched signer reads
- [x] fix 3: ancestry memo
- [x] 46/46 suites pass; `guide.sh` passes (installed and
  working-tree hooks)
- [ ] measure on the same pair
- [ ] install, rerun 2606-sims
