# History pruning (front-truncation)

- ADAPTED 26/09/02 to the git-state model; the original
  (worktree-era: trees, posts.lua, likes/ dirs) is in git
  history and mostly void -- see "What the redesign changed"
- goal: bound history growth; commits + payloads grow
  forever (the packed floor in the sims grows with N)
- nothing implemented yet

# Mechanism: shallow graft (unchanged)

- boundary `c1` = newest anchor older than `T_keep`
- write `shallow` (bare repo: `<dir>/shallow`), reflog
  expire, `gc --prune=now`
- `c1` keeps its REAL, network-shared hash; only ancestors
  are forgotten
- `--orphan` and interior rewrite stay rejected: both mint
  new hashes and break merge-base with peers

# Two knobs (unchanged)

- `T_fork` (7d/100): consensus freeze, fires EARLY
- `T_keep` (30d/500): retention, prunes LATE
- `keep = { time, posts }` in constants, dual polarity
- rolling auto: every peer flattens on its own schedule
- straggler past `T_keep`: re-anchor (repost as new)

# What the redesign changed

- every commit carries the EMPTY tree: there is no tree to
  keep or rm -- Track A/B and the old MEASURED section are
  VOID
- payloads = blobs at `refs/payloads/<cid>`: refs point at
  BLOBS, not commits, so they pin NO ancestry, and
  `get payload` never touches the commit
    - old payloads SURVIVE a graft for free (keep = default)
    - forgetting them = deleting refs below the boundary
      (remove-blob territory, separate decision)
- states: same (blob refs, no pinning); with the
  260902-snapshots branch, anchors below the boundary are
  already deletable
- `G.actions` tombstones keep author/reps/revoke forever:
  the old "metadata fold" mostly EXISTS already
    - still dies with the commit: kind, time, backs
      (`ACTION.read`), and the SIGNATURE (provenance --
      irreducible, as before)
- begs: `refs/begs/*` point at COMMITS: still pin ancestry
  (old Blocker 2): drop begs below the boundary, extending
  recv's stale-beg pass

# Guards

- genesis identity: compare `refs/genesis` (every chain has
  the ref now) instead of `rev-list --max-parents=0`, which
  reports the shallow boundary on a pruned peer
- reject forks below the boundary: REVIVE 260818-prune P2
  (depth rule, pure git, before any state read; both peers
  compute the same count)
    - verify-below-boundary = un-prune = DoS: reject only
- blacklist repeat deep-fork offenders: 260819-blacklist

# Implementation order

- 1: `keep` constant
- 2: beg drop below boundary (recv stale-beg pass)
- 3: genesis guard on `refs/genesis`
- 4: P2 depth reject (revive from done/260818-prune.md)
- 5: flatten: boundary select + shallow + gc
- 6: rolling-auto trigger (only after 2-5)
- metadata fold: only if pruned-cid `get metadata` matters
  (kind/time/backs into G tombstones, eager)

# References

- done/260818-prune.md: P2 depth reject, built + reverted
- done/260723-fork-7day.md: the hard-fork rule
- 260902-snapshots branch: state anchors (complementary:
  that prunes STATE, this prunes HISTORY)
- 260819-blacklist.md: repeat offenders
