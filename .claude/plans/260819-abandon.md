# 260819-abandon

- what may be abandoned, and what falls with it
- born from 260818-prune.md P1 discussion (collateral drops)
- phases: discuss -> strange tests -> settle -> implement

# Phase 1: discuss

## Sensible cases

- C1 regret: drop my own unsent tail (before any send)
- C2 hardfork escape: drop my unsent tail after a refused
  send, then recv + repost (why abandon exists)
- C3 sim rewind: drop a received suffix (tests, guide.sh,
  `--now` simulations; not a real network case)
- C4 beg: drop a parked beg (already a special case: one ref)

## Key fact: only unsent drops are durable

- a received action is valid community history: the next
  recv brings it back (nothing marks it revoked)
- so abandoning received history is only meaningful on an
  isolated peer (C3); durable abandon = my unsent tail

## Option O1: order-based abandon

- `list order`, cut at the aid, drop the order-suffix
- kept prefix is DAG-closed (order is topological)
- but may match NO existing commit: must materialize new
  merges to rebuild a tip ("fix the tree somehow")
- adds power ONLY for interleaved received history, which
  resurrects on next sync anyway
- complex: partial-branch tips, snapshots for new merges

## Option O2: restrict to a linear suffix

- refuse when `tip..HEAD` holds a commit without an aid
  (a sync merge); error: `chain abandon : crosses a merge`
- landing ON a merge is fine; crossing one is not
- beg-attach likes have aids: still abandonable
- covers C1-C4: unsent tails are linear by construction;
  README/guide rewinds are linear received suffixes
- collateral impossible by construction; ~5 lines

## O3: `abandon --keep <aid>` (dual form)

- names the last KEPT action: its commit becomes HEAD,
  everything above it drops
- collateral is explicit (you named the survivor), so the
  crossing-a-merge rule does not apply to this form
- covers "revert to fork point F": `abandon --keep F`
  (impossible under O2 alone: any aid puts M in range)
- `abandon a1` == `abandon --keep F` when F is an action
- implementation: same code, `tip = cid` not `cid^1`
- hole: a landing point that is itself a sync merge has
  no aid; name an action below it and lose a bit more

## Leaning: O2 + O3

- O1's extra power is illusory (resurrection) and costly
- O2 keeps the default safe; O3 makes collateral explicit
- one boundary rule serves both: landing commit must pass
  `STATE.has` (260818-prune.md P1, deep fork points)

# Phase 2: strange tests (before settling)

- DONE: `tst/abandon-strange.lua`, all pass, 5 findings:
    - collateral confirmed: abandon a1 drops b1 b2 M,
      lands on the fork point, kills the b payload anchors
    - resurrection confirmed: next recv restores the b's,
      order AND payload anchors (self-healing)
    - own-sent action resurrects too: durable abandon is
      ONLY the unsent tail (the key fact, now proven)
    - landing ON a sync merge works; posting on it works
    - beg-attach like: 2-parent commit WITH an aid;
      abandoning it drops the like and its beg together
- not yet covered (need prune P3 or the new design):
    - landing tip below the prune boundary
    - `--keep` forms (O3 not implemented)

- abandon first action of a merged branch (today: drops
  the sibling branch; O2: refused)
- abandon deepest action of MY branch after a recv merged
  it (mine but sent: comes back? refused?)
- abandon crossing two nested merges
- abandon then recv: dropped received actions must return,
  payload anchors restored
- abandon own unsent tail then recv then repost: no extra
  reps (the README hardfork flow, as a test)
- abandon a beg-attach like (merge WITH an aid)
- abandon the tip itself (minimal case)
- abandon genesis / unknown aid (refused today: keep)
- abandon whose landing tip is a fork point below the
  prune boundary (needs 260818-prune.md P3 to exist)
- `--keep` the tip itself (no-op?), `--keep` across nested
  forks, `--keep` where the wanted landing is a sync merge

# Phase 3: SETTLED (26/08/19)

- O1 rejected: powers only received-history carving, which
  resurrects on recv (proven by tests 2 and 3)
- `abandon <aid>` (O2): refuse when `cid^1..HEAD` holds a
  commit without an aid (a sync merge)
    - error: `chain abandon : crosses a merge`
    - landing ON a merge stays legal (test 4)
    - beg-attach likes stay abandonable (test 5)
- `abandon --keep <aid>` (O3): cid becomes HEAD, all above
  drops; collateral explicit, no crossing rule
    - `--keep` HEAD's own aid: no-op, allowed
    - a sync-merge landing point has no aid: name an
      action below it (documented hole)
- both forms: landing commit must pass `STATE.has`
    - error: `chain abandon : settled action`
    - subsumes 260818-prune.md P1 (updated there)
- begs, genesis, unknown aid: unchanged

# Phase 4: implement

- abandon.lua: crossing check (log tip..HEAD, any commit
  without an action file -> error)
- abandon.lua: `--keep` form (tip = cid, skip crossing)
- freechains.lua: argparse `--keep` flag
- tests: extend abandon-strange.lua (refusals, --keep);
  keep cli-abandon.lua green
- README/guide: `--keep` one-liner in API list
