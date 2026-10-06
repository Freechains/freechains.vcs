# Bug: fork winner depends on the replay path

# Symptom

- peers with the SAME HEAD list different `list order`
- a fresh clone may disagree with every live peer
- found by 2606-sims `p2p/p2p.lua` (hubs-59, 59 peers)
    - 20 posts, 11 merge syncs: 4 of 59 peers differ
    - `/x/papers/2606-sims/.claude/plans/260924-topology.md`
- same failure on `main` (0.21.0 installed) and on
  `260914-tree-trash` (src)

# Repro (6 peers, 4 posts, open chain)

- keys K1, K2, K3; all `--now` pinned
- A: init; B, C, D clone A
- A posts a1 (K1); B posts b1 (K2), concurrent
- D recv A: D has a1
- A recv B: M1 = a1 + b1
- D posts a2 on a1 (K2)
- C recv A (M1), posts c1 on M1 (K3)
- D recv A: M2 = a2 + M1
- E clones D: HEAD M2
- D recv C: M3 = M2 + c1
- E recv D: fast-forward to M3
- Z clones D: fresh
- D, E, Z: same HEAD M3, when the cid tie favours M2:

```
D (merger)   b1 a1 a2 c1
E (FF)       b1 a1 c1 a2
Z (clone)    a1 b1 a2 c1
```

- cids vary per attempt: retry until the tie favours M2
- script: `2606-sims` scratch `min2.sh` (to be ported)

# Cause 1: the floor is above an inner fork

- `winner(G, a, b)` says: G = state at the fork floor
- `meet` passes the RUNNING replay state instead
- replay starts at the sync's `oct` snapshot, which depends
  on the receiver's HEAD
- `oct` can sit ABOVE an inner fork's `up`
    - then `climb(G, com, up)` is a no-op
    - G already holds one side of that fork
- E: `oct` = M1, inner `up` = a1
    - G has b1, so K2 = -500 (post cost)
    - a2's side (K2) loses: c1 first
- D: `oct` = a1: K2 unknown, 0 = 0: cid tie: a2 first

# Cause 2: `meet` pre-applies `up`

- `meet` climbs to `up` before choosing the winner
- a full replay of M3 meets (M2, c1) first, `up` = a1
- a1 is applied there, before M1's own fork is decided
- Z: a1 lands before b1, although b1 wins M1's tie

# Side effect: snapshots of loser commits

- `action.lua` apply: "first write is the commit's
  own-lineage state" is FALSE
- a commit first applied as a loser, on top of the winner,
  is snapshotted WITH the winner's actions
- e.g. C recv a merge (FF): snapshot(loser) holds both posts;
  the merger and the author keep a clean one
- `now` is already folded from own ancestors; actions, reps
  and order are not

# Fix ideas

- define: state at a commit = function of the DAG below it
- `winner`: reps from the own-lineage state at the pairwise
  merge-base `com`, never from the running replay
    - needs clean snapshots (below)
- snapshots: build a commit's state only from its parents'
  states; never write one inside a replay that holds siblings
- `meet`: decide the winner before applying `up`'s ancestry,
  or replay each side from its own floor
- check cost: one `STATE.read(com)` per inner fork

# Open

- reference order = fresh replay from genesis, once fixed
- `hardfork()` compares HEAD orders: same path issue?
- other `replay` callers: sweep, discard, begs
- 2606-sims p2p runs blocked until fixed
