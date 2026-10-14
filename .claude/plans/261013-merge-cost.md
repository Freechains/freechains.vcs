# Merge cost and range walks (26/10/13)

# Context

- found in 2606-sims, full usenet local-first run (stopped at 8.8k)
- build: ia-optim 175f19e (git-batch); code refs from there
- DAG: 1.35 sync merges per action; 98% merge new actions on both
  sides (real merges, not policy waste)
- kept peers: `2606-sims/p2p/.freechains-keep/usenet-full-lf-slot`

# A. Range walks with merge dates 0

- sync merges carry commit date 0: git's default `A..B` walk
  (date heuristic) stops early and returns wrong sets
    - example: `rev-list s..r` = 5 with r an ancestor of s
      (`--topo-order`: 0)
    - 6 of 90 sampled ranges wrong on the kept chain
- effects:
    - false `voided : <cid>` lines on a fast-forward with merges
    - sites below may see wrong commit sets
- sites (no `--topo-order` today):
    - `sync.lua:222` new commits `loc..rem` (ff decision, replay)
    - `sync.lua:321` voided listing
    - `sync.lua:439` my side's vote targets `BASE..OLD`
    - `consensus.lua:170` collect_keys `com..tip` (fork winner)
    - `discard.lua:168,235` (check)
- fix: `--topo-order` on every range walk
    - cost: 7 -> 11 ms per walk at 8.8k (with commit-graph)
- not done: merge date = max(parent dates)
    - format change (merge hashes), validation rule
    - not sufficient: posts may be dated up to 1 h before
      ancestors; crafted remote dates
- check: no false `voided` on the 50-commit ff case
  (receiver s~8, source s, kept usenet-5k-lf-slot S1)

# B. Merge backs walk grows with DAG width

- one-merge pull: 0.58 s at 500 actions, 1.07 s at 8k
- profile at 8k: `ACTION.backs` (`action.lua:188`) from
  `apply` (`action.lua:325`, `:406`): 1424 `is` for 3 calls
- cause: `G.tips` shortcut only for one parent; a merge walks
  down through merges until the nearest actions
    - nearest actions of a merge: 13 at 0k, 55 at 5k, 80-120 at
      6-8k; walk visits avg 200-300, max 1023 commits
- fix: backs(ps) = union of tips(p), p in ps
    - tips(p) = {p} if action, else snapshot `meta.lua` tips
    - no snapshot: recurse on its parents (memo per process)
    - same result as the walk (it stops at actions)
- check: same backs as the walk over all merges of the kept chain;
  same HEAD, order, refs, reps on the prof2 pulls

# C. Other costs (later)

- snapshot write `state.lua:916`: 0.2-0.3 s per commit at 5k
    - tree_id sort comparator `state.lua:262`: 400k calls per
      50-commit pull; precompute keys
- snapshots on every commit: only tips and merges needed?

# D. Fewer git processes per pull (26/10/13, done)

- 41-commit pull at 8.8k: 456 git processes = 3.3 s of 4.1 s
- D1: `range(com, tip)` memo, one `rev-list --topo-order` per
  pair: the climb's floor test (was one `merge-base
  --is-ancestor` per commit) and the winner's signers
- D2: winner reads the floor's `open` and the signers' members in
  one batch (`STATE.peek`), not the full snapshot; full
  `M.state` only without a snapshot
- after: 294 processes; left: cat-file loads 56, ranges 69,
  tips 40, ssh verify 31, pair merge-base 25, listings 21
- next ideas (not done): ranges in Lua from one `--parents`
  walk; batch ssh verify

# Results (26/10/13, ia-optim, uncommitted)

- A: `--topo-order` at the 6 sites (sync 3, consensus 1,
  discard 2)
    - old build counted signers outside com..tip: 3 of 46 winner
      inputs wrong on one 8.8k pull (e.g. ka 2, right 1)
    - deterministic (same DAG, same wrong set): peers converged;
      mixed builds would not
    - one extra snapshot (a corrected sub-merge); HEAD, order same
- B: `STATE.tips` (batched meta read) + TIPS memo in `apply`;
  `backs` walks only commits without known tips
- C: `tree_id` keys once, hex->bin memo; `put` takes the tree id
  (no second sha1); dropped unused mktree lines
- tests: 46/46 suites, guide.sh (bash) pass (after A-C and D)
- old vs new, same HEAD/order/refs on 9 pulls (5k, 8.8k keeps);
  false `voided` gone (5 -> 0)
- wall, best of 3-5:
    - 1 merge at 8k: 1.08 -> 0.67 s (ff), 1.12 -> 0.72 s (mg)
    - 1 merge at 500: 0.62 -> 0.63 s (unchanged)
    - 8 commits/5 merges at 5k: 0.64 -> 0.56 s
    - 41/25 at 8.8k: 4.23 -> 4.09 s; 50/33 at 5k: 3.32 -> 3.19 s
- profile (inflates Lua): 9.8 -> 6.8 s, 1.6 -> 1.0 s;
  sort comparator calls 461k -> 155k; mg-8000 git processes
  165 -> 47
- with D (best of 3; old -> A+B+C -> +D; same outputs as A+B+C):
    - 41/25 at 8.8k: 4.21 -> 4.05 -> 3.00 s
    - 50/33 at 5k: 3.42 -> 3.19 -> 2.29 s
    - 6/4 at 8.8k: 1.02 -> 0.90 -> 0.79 s
    - 1 merge at 8k: 1.06 -> 0.68 -> 0.62 s (ff), 1.12 -> 0.72
      -> 0.68 s (mg)

# Status

- [x] A: `--topo-order` on range walks
- [x] B: backs from snapshot tips
- [x] C: tree_id/put quick wins
- [x] D: fewer git processes per pull (456 -> 294)
- [ ] install; rerun 2606-sims full
