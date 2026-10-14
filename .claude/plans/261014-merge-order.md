# Same posts, different merges: hard fork (26/10/14)

# Context

- found in 2606-sims: usenet 2k, local first, build 5ebae95,
  action 405, pull L04 <- M1 (1989-04-12), aborted run
- same action set on both sides: L04 differs by merges only
- orders swap two old posts (e4e3f4a4, 7647da91) at 401 of 405
- settle age 182.9 h > 168 h (`C.time.fork`): `sync.lua:97`
  `hardfork` refuses; old build 175f19e refuses too
- kept peers: `2606-sims/p2p/.freechains-keep/usenet-2k-lf-hardfork`
- code refs: ia-optim 5ebae95

# Cause

- order of a merge = winner's order + loser's replay
  (`sync.lua` recv, `consensus.lua` replay)
- so the order depends on which branches met first, not only on
  the action set
- 3 concurrent posts x[K1] y[K2] z[K3], K1 > K2 > K3, K2+K3 > K1:
    - A: (x + y) + z -> x y z
    - C: (z + y) + x -> y z x
- if A and C do not sync for 7 days (chain time), each one's order
  is settled, and the winner's order reorders the loser's: refused
- sims: `useful` (`p2p.lua:274`) skips pulls with no missing
  action, so merge-only differences never reconcile; real peers
  would pull (git sees new commits)

# Test

- `tst/hardfork-merges.lua` (ia-optim): A, B, C post x, y, z at
  once; D holds z alone; C merges y then x; A merges y then z;
  8 days later both post and sync both ways
- expected: both accept, same final order
- today: A <- C accepts, C <- A fails `chain sync : hard fork`
- not in `Makefile` yet (suite stays green)

# Open questions

- 1. order as a function of the action set (DAG without merges)?
    - deterministic over posts only, merge structure irrelevant
    - cost: recompute or a canonical merge at every sync
- 2. or relax `hardfork`: ignore reorders among actions both
  sides already hold (only new actions before my settled ones)?
    - settled posts may still move: reps, voided likes change
- 3. settle age from receipt time: does not help here (A held x
  first for 8 days); drop this option?
- 4. sims: keep `useful` by action set (models no-traffic quiet
  peers) or pull on any new commit (models git)?
- 5. add `hardfork-merges.lua` to `Makefile` now (red) or with
  the fix?
- 6. same issue in the paper (3.6, 3.8): a known limit to state,
  or a rule to change?

# Option 2: post-only DAG (26/10/14, chosen to try in ia-optim)

- goal: same posts -> same DAG -> same order (no path dependence)
- sync creates no commit: fetch the missing posts only
- a post joins branches: parents = all current tips
    - a git merge commit that carries the payload
    - its state is still a function of its ancestors (snapshots ok)
- between posts a peer holds several tips (refs), not one HEAD
- order of a tip set: canonical N-way rule, independent of which
  pairs met first; local cache keyed by the tip set, never stored
  in a shared commit
- likes, revokes, begs: actions, so they join tips as posts do

# Option 2: interface

- CLI commands and arguments unchanged
- behavior changes:
    - `list tips`: may print several tips
    - `list dag`: no sync merges; actions with 2+ parents
    - `sync recv`: no new merge commit; `voided` lines stay
    - `chains add clone`: fetches every tip ref
- 2606-sims `p2p.lua` pull script reads `HEAD` (nc, nb, na):
  needs the tip refs instead

# Option 2: hard parts

- define the N-way order: pairwise winner + replay today
  (`consensus.lua` winner/replay); generalize so the result
  depends on the tip set only; prove it
    - e.g. fold tips sorted by a key fixed by the set (reps at
      the common fork, then hash)?
    - must agree with the order stored by a post that joined
      the same tips
- hard fork (`sync.lua:97`): compare my tip-set order vs the
  order after the fetch
- `discard.lua`: assumes one surviving tip where HEAD lands
- refs per tip; HEAD (or a local ref) for a single read point
- post tree = union of the parents' trees plus the payload
- cost: tip-set changes need incremental recompute (2021 design
  sorted the whole DAG: 100 s)
- tests: 27 suites use merges (`MERGE`, `DRYMERGE`, git-merge,
  cli-get-merge, hardfork-*, consensus*, repl-*): rewrite or
  drop; `hardfork-merges.lua` must pass

# Option 2: steps

- 1. N-way order rule on paper + small Lua model; check path
  independence on random DAGs
- 2. storage: tip refs, post with N parents, tree union
- 3. state of a tip set (virtual merge, cached locally)
- 4. sync: fetch only; winner/replay over tip sets; hard fork
- 5. discard, sweep, list, get over tip sets
- 6. port tests; run hardfork-merges, guide.sh
- 7. 2606-sims: pull script without HEAD; rerun usenet 2k lf

# Option 2b: canonical merge (26/10/14, implemented)

- same goal as option 2, `main` kept as the one read point
- sync joins the tips of both sides in ONE merge commit:
    - tips: nearest actions of both mains, `--independent`
    - parents sorted, date 0, unsigned, empty message
    - same tip set -> same commit on every peer
    - same actions -> same main: git sees nothing new
- a post's parent is that merge: it joins the tips
- merge state = fold of its parent set (`consensus.lua`):
    - rank: reps at the set's merge-bases (dictator, reps, cid)
    - criss-cross floor: the canonical merge of the bases
    - winner's own state, then each other side replayed
    - a failure voids the rest of its side only
    - 2 parents: same as the old pairwise winner
- voided tips: sync drops them and folds again
    - nothing is ever built on a voided action
    - an action on a voided back: "invalid <kind> : voided back"
- hard fork: old main's order vs new main's order
    - skipped on a plain fast-forward (no merge among the news)
- unchanged: transport (push/fetch `main`), hook, clone, post,
  like, discard, list
- legacy merges: folded by the same rule (parent order ignored)
    - criss-cross legacy merges may rank apart from before
    - existing snapshots are never rewritten

# Option 2b: vs option 2

- no tip refs, no multi-ref push/fetch, no N-parent actions
- sims `p2p.lua` pull script reads `HEAD`: still works
- `list dag`: merges are transparent (backs), as before
- suggest *won't do*: option 2 storage (tip refs)

# Status

- [x] cause found, reproduced on kept peers and in a test
- [x] Q1: option 2 as 2b (canonical merge) in ia-optim
- [x] Q3: receipt time dropped (does not help)
- [ ] Q4 sims: `MERGES=1` meanwhile; with 2b same actions give
  the same `HEAD`, so `useful` may stay by action set
- [x] Q5: `hardfork-merges.lua` in `Makefile`, passing
    - precondition flipped: same main, same order (the fix)
- [ ] Q6 open (paper 3.6, 3.8)
- [x] steps 1-6 as 2b:
    - N-way rank + fold; path check: `merge-paths.lua`
      (8 seeds; old code fails seed 7)
    - `discard-strange.lua`: merge parent by membership
    - 48/48 suites, `guide.sh` pass (working-tree hooks)
- [ ] step 7: install, rerun 2606-sims usenet 2k lf
