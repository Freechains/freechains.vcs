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
    - if `age >= C.time.fork` (7 days): refuse, `chain sync : hard fork`
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
    - in apply/replay, after `advance`: `entry.ctime = G.now` (DONE)
    - required by `hardfork()`; old snapshots lack it (fresh chains)
- `src/freechains/chain/sync.lua`, `hardfork()` (DONE)
    - settled index: walk back from the tip while
      `G.now - entry.ctime < C.time.fork`; prefix compare as before
    - fork point = first ORDER divergence, not the git merge base:
      a ff (`hardfork-ff.lua`) has base == my tip, age 0, yet may
      insert inside my settled prefix
    - keep call site "only when the remote wins"
    - count branch and action-file reads removed
- `src/freechains/constants.lua`: drop `fork.actions`, `fork.time` ->
  `time.fork` (DONE); move to genesis constants if per-chain
- `src/freechains/chain/discard.lua`: unchanged; comments updated (DONE)
- `STATE.write`: `ctime` persists with the entry (whole table)
- commits/DAG: untouched

# Tests (`tst/`)

- fresh loser with weeks-old timestamps: refutable for 7 days after
  merge; refutation propagates to a peer that merged it
- refutation after 7 days of consensus time: refused (hard fork)
- 100+ action loser flood: no effect on settling
- old winning branch reordering settled prefix: refused (as today)
- stale member (loser): accepted, appended; (winner): refused
- new `tst/fork-ctime.lua`: tests 1-3 above (100 junk in test 1)
- `fork-100-posts.lua`: flips, 100 posts in 150h no longer entrench
- `fork-7-days`, `hardfork-ff`, `hardfork-shared`, `cli-discard`:
  same verdicts under `ctime`, unchanged

# Docs

- `doc/` consensus/hard-fork text: settle by consensus time, no count
- `guide.sh` 7-day section: expected output unchanged unless count
  was exercised

# Follow-up: group the entry times

- `rules.lua` entries hold three flat times: `time` (declared),
  `now` (DAG-causal max, "too old" bound), `ctime` (order-based
  chain time)
- regroup as `time = { declared=, dag=, order= }`
    - not "peer": same value on every peer with the same DAG
    - `time.declared = nil` keeps the consolidation sentinel
      (`ordered()`, discount scan, ~10 sites)
    - `M.now()`, `hardfork()`, `sync.lua` merge fold follow
- `get metadata`: keep the action file's `time`; expose `order`
  as the late-action hint (`order - time`)
- rename only, no semantic change; old snapshots incompatible
  (fresh chains, as with `ctime`)

# Open

- window as genesis constant vs global constant: decide with paper
- `ctime` for merge commits: fold parents (as `RULES.now` does)
