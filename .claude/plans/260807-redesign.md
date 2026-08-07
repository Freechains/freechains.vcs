# Redesign from scratch: state trust + verification

# Next steps (run on other machine)

- decide: verify remote state vs local-only state (see Q4/Q5)
- copy failing test `tst/bug-forged-state.lua` (already on main)
- run `cd tst && lua5.4 bug-forged-state.lua`
    - confirm which scenarios fail on main
- create `src/chain/consensus.lua` skeleton
    - move: `ancestor`, `octopus`, `consensus`, `replay`
    - from scratch, no code from other branches
- wire verification into sync recv AND clone
    - one operation: `rev-list tip --not frontier`

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
