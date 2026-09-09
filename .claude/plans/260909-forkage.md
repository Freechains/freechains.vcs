# Settle by Consensus Time (fix freeze-by-flood)

# Context

- paper review (2606-vcs, items 2.9 + 2.13): freeze-by-flood
    - `hardfork()` settles by position (last 100 of local order) and
      by DECLARED timestamps inside that window
    - a loser branch with old timestamps, or 100+ actions, settles
      itself on arrival at any peer that merges it
    - the honest refutation (discard + dislike) is then refused there
- design discussion (2026-09-09), options weighed:
    - reject old forks win or lose: cheap boundary noise (500 reps
      forces a lagging peer to discard); rejected
    - local-arrival freeze: wall-clock, receipt gap; rejected
    - count criteria: floodable or non-monotone; rejected
- decision: keep current semantics (accept losers, refuse a WINNER
  that reorders the settled prefix, 7 days), but measure settle age
  by CONSENSUS TIME and drop the action count
- paper side: `2606-vcs/.claude/plans/260905-review.md` (2.9/2.13)

# Rule

- consensus time of an action = chain time at its replay in the
  local order = max(declared time, consensus time of predecessor)
    - function of the DAG order; same on any peer with the same DAG
    - a loser merged today gets today's consensus time, whatever its
      declared dates
- settle check (only when the remote wins, as today):
    - `age = ctime(tip) - ctime(fork point)`
    - if `age >= C.fork.time` (7 days): refuse, `chain sync : hard fork`
- losers: accepted, appended, loose for 7 days after the merge,
  refutable by ordinary consensus in that window
- no count criterion (100 actions dropped)
- threshold fixed per chain (genesis constant; 7 days default;
  chats may use less); per-peer/random thresholds widen disagreement

# Properties

- honest connected peers: identical ctime for shared history; differ
  at the tip by gossip lag; verdicts differ only for a WINNING branch
  forking within that lag of the 7-day mark (rare, recoverable)
- cheap attacker: his branch loses, appended, loose, refutable;
  cannot trigger a verdict; not recurrent
- majority attacker: can reorder the loose window anyway (out of
  model); the 7-day settle bounds him in time
- idle forum: attacker's farm is a fast-forward, enters unchallenged;
  refutation later forks too far back; only revoke (rule 3.d) or a
  social hard fork (inherent; paper limitation)
- refutation propagates to every peer while the farm is loose there

# Implementation

- `src/freechains/chain/rules.lua`
    - in apply/replay, after `advance`: `entry.ctime = G.now`
    - optional cache; recomputable by walking the order
- `src/freechains/chain/sync.lua`, `hardfork()`
    - replace the last-100 timestamp walk with one comparison:
      `G_loc.now - ctime(fork point) >= C.fork.time`
    - fork point = pairwise merge base (`oct`), as today
    - keep call site "only when the remote wins"
    - remove the count branch
- `src/freechains/constants.lua`: drop `fork.actions`; keep
  `fork.time`; move to genesis constants if per-chain
- `src/freechains/chain/discard.lua`: unchanged; comments updated
- `STATE.write`: `ctime` persists with the entry (whole table)
- commits/DAG: untouched

# Tests (`tst/`)

- fresh loser with weeks-old timestamps: refutable for 7 days after
  merge; refutation propagates to a peer that merged it
- refutation after 7 days of consensus time: refused (hard fork)
- 100+ action loser flood: no effect on settling
- old winning branch reordering settled prefix: refused (as today)
- stale member (loser): accepted, appended; (winner): refused
- rewrite existing hard-fork tests for the new age computation

# Docs

- `doc/` consensus/hard-fork text: settle by consensus time, no count
- `guide.sh` 7-day section: expected output unchanged unless count
  was exercised

# Open

- window as genesis constant vs global constant: decide with paper
- `ctime` for merge commits: fold parents (as `RULES.now` does)
