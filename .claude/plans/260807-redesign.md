# Redesign from scratch: state trust + verification

# Next steps (continue on other machine)

- implement fix in consensus.lua (design below), pass 1:
    - split `commit` -> `check` + `play`
    - `state_link`, `verify`, `frontier`
    - wire recv + clone
    - covers scenarios 1 (tip), 2 (interior), 4 (clone)
- pass 2: `state_merge` + begs
    - covers scenario 3 (merge side)
- run full suite: only bug-forged-state red between passes

# Done

- [x] all 4 holes proven red in `tst/bug-forged-state.lua`:
    - 1 diverge tip, 2 interior, 3 merge side, 4 clone
    - 2 was GREEN by accident: forged `%at=1120` tripped the
      NEXT commit's `now` check (`PEAKS = max(%at, now)`);
      stealthy forger pins dates to `now` (@1100): passes
- [x] decision: verify remote state (not local-only), Q4/Q5
- [x] `src/freechains/chain/consensus.lua` extracted + committed
    - `octopus`, `consensus`, `commit`, `replay` (climb/meet)
    - `hardfork` stays in sync.lua; suite green
- [x] FF special handling removed from recv (unified w/ diverge)
    - consensus: ancestor rule (contributing nothing cannot win)
        - zero-reps FF suffix tied, fell to hash: loser machinery
          on descendants FFs, no MERGE_HEAD, crash (cli-recv)
    - early FF hardfork fast-fail deleted: read REMOTE committed
      order (trust hole); now one post-replay check vs DERIVED
    - state probe after final ref update: covers FF tip AND
      diverge w/ no surviving loser (was unchecked before)
    - suite 37/37 green; bug-forged-state still red (interior)

# Fix design: context-free verification (consensus.lua)

- idea from [260802-state-verify.md](260802-state-verify.md),
  code written from scratch

## split `commit` in two

- `check(hash)`: context-free, cacheable
    - signature, kind, mode (paths/status)
    - state commits: state-link (below) + `now` vs PEAKS
- `play(G, hash, beg)`: order-dependent
    - the `apply` calls + `G.order` append
    - `replay` calls `play`, not `check`

## state-link (1-parent state commit S)

- rule: `state(S) == apply(state(P), action(P))`, P = parent
- read G2 = 4 state files from P's own tree
- derive P's action: trailer + metadata file + sign key
- re-apply onto G2, compare `serial` of `authors`, `posts`
    - skip `order`: honest peers may disagree (own bug)
    - `now` checked separately (PEAKS)
- beg ambiguity: signed post w/o reps flag -> try both readings
- like-on-beg: P is 2-parent `-X ours` merge
    - pre-apply beg side from P^2 first

## state-merge (2-parent state commit)

- replay one side from `octopus(p1,p2)` anchored at its
  committed state, compare
- not O(1), accepted (measured +60..90% on merge-heavy)

## verify walk + frontier

- `verify(tip)`:
    - `git rev-list --reverse tip --not refs/freechains/verified`
    - `check` each (genesis: 0 parents, skip)
- `frontier(tip)`: advance `refs/freechains/verified`
    - local, untracked: no peer can forge it
    - memoized forever: content-addressed facts

## wiring

- recv: `verify(rem)` + every `refs/begs/*`
    - BEFORE `G_oct` is read from any tree
- clone (chains.lua): `verify(main)` after clone
    - remove chain again on failure
- destroy: `frontier("HEAD")` after reset
- keep `write`+`diff` tip probe as end-to-end check (for now)
    - no longer FF-only: runs whenever remote wins w/o loser merge

# Ground rules

- start from this point, evolve from scratch
- no code reuse from other branches
    - `260802-bug-forged-state` is reference only
- related plans are pointers, not dependencies:
    - [260802-redesign.md](260802-redesign.md)
        - Lua DB as action layer, join commits, evict payloads
    - [260802-state-verify.md](260802-state-verify.md)
        - parent-relative verification (branch, done, not merged)
    - [260803-forged-state.md](260803-forged-state.md)
        - replay-relative verification (way-station)
    - [state-hash.md](state-hash.md)
        - shipped FF tip compare

# Discussion (Q&A, 260807)

## Q1: is the problem trusting remote state?

- yes
- state does two jobs: RECORDS + ANCHORS
- record is checked (FF tip) or ignored (diverge)
- anchor is trusted:
    - `G_oct` loaded raw from commit tree
    - feeds replay + `consensus()` (merge control)

## Q2: forged state can come from sync?

- yes, three ways:
    - FF: interior commits (only tip checked)
    - diverge: loser side arrives as parent-2
    - merge side: forged beg merged by a `like`

## Q3: also from clone?

- yes, worst hole
- `chains add clone` validates nothing
- entire history accepted verbatim

## Q4: should the fix ignore any remote state?

- the "never trust the tree" option:
    - never read state from trees
    - keep local commit -> state cache
    - deletes the attack class, no verification code
- cleaner endpoint

## Q5: local-only state, costs?

- committed state becomes vestigial
    - pulls against redesign (every commit carries state)
- `destroy` relies on in-tree state to restore after reset
- loses detection:
    - silently ignores a peer's lie vs refusing/flagging
    - detection is input to reputation later
- clone still replays genesis -> tip to build local state
    - same cost as verifying it

## Q6: consensus/apply needed in both sync and clone?

- yes, both reduce to one operation
- verify/replay the set: `rev-list tip --not frontier`
- clone = base case: empty frontier, O(history) once
- sync = incremental

## Q7: move machinery to consensus.lua?

- yes
- `src/chain/consensus.lua`
- holds: `ancestor`, `octopus`, `consensus`, `replay`,
  context-free checks, frontier walk
- self-contained verification machinery
