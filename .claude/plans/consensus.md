# Consensus: Fetch Validation Pipeline

## Git's Built-in Validation (fetch)

On `git fetch`, git validates automatically:

- **Object integrity** — SHA hash of every object matches
  content
- **Object graph** — commits reference valid parents, trees,
  blobs
- **Transfer protocol** — packfile checksums, no corruption

These guarantees are free — no freechains code needed.

## Consensus Rule

The side whose first divergent commit (immediately
after common ancestor) has the **earlier author date**
wins. Winner's branch is accepted as-is. Loser's
branch is validated commit-by-commit.

Both peers arrive at the same decision because the
dates are embedded in the commits.

## Validation (loser branch)

After fetch, the loser's commits are validated one by
one (oldest first) against the winner's state:

- **Reputation thresholds** — author has enough reps
- **File-op costs** — author can afford the operations
- **Merge compatibility** — commit merges cleanly with
  winner's tree (dry-merge per commit)
- **Genesis immutability** — `.freechains/config.lua` never
  changes
- **Mode enforcement** — per-commit tree diff vs parent;
  every changed path's operation must be permitted by the
  chain's `mode` field. See [operations.md](operations.md).

On first validation failure: discard that commit and
all subsequent loser commits.

## Merge (after validation)

Current implementation uses `git merge --no-commit`
followed by writing state files and `git commit`. This
produces a merge commit with two parents + state files
in a single commit. Equivalent to plumbing for the
non-conflict case.

State commits ("freechains: state") are created:
- After merge in recv (to persist replayed state)
- At genesis (initial pioneer state)

State files (`authors.lua`, `posts.lua`) are written to
disk on every command but only committed to git after
merges and at genesis. Post/like commits do NOT include
state files.

### State Commits as Checkpoints

State commits serve as **replay checkpoints**. The
merge-base always has state files in its tree (post/like
commits carry dirty state on disk, but the merge-base
is always reachable via a state commit in the shared
history). Current implementation loads state directly:

```lua
git show com:.freechains/state/authors.lua
git show com:.freechains/state/posts.lua
```

No backward walk is needed — state files are always
present in the tree at every commit (dirty but readable).

### Linearity Guarantee

Walking backwards from the merge-base is guaranteed to
be **linear** (no forks) because every merge is followed
by a state commit. This means a state commit always
appears between the merge-base and any merge point in
the shared history:

```
... → merge → state_commit → P1 → P2 → P3 (merge-base)
      ↑                                ↑
      never reached                     start walk back
```

The state commit acts as a **barrier** — it stops the
backward walk before encountering any non-linear
history (merge commits). Without this guarantee, the
backward walk could hit a merge commit with two parents,
making traversal order non-deterministic.

This is why "only after merge" is sufficient and
critical: it guarantees a checkpoint between the
merge-base and any fork in the DAG.

### Tie-Breaker

When two divergent branches have the same first-commit
author timestamp, the consensus winner is determined by
**commit hash** (lexicographic comparison). This ensures
both sides pick the same winner regardless of which is
local vs remote:

```
if l < r then
    fst, snd = loc, rem
elseif l > r then
    fst, snd = rem, loc
elseif loc < rem then       -- hash tie-breaker
    fst, snd = loc, rem
else
    fst, snd = rem, loc
end
```

## Trust Levels

See [replication.md](replication.md) for the full
owner/non-owner trust table. Owner-to-owner replication
skips freechains validation entirely. Non-owner
validation is future scope.

## Hard Fork Rule


Walking my own order back from the tip, everything older
than **7 days** — or more than **100 entries** back — is
SETTLED. A sync is a hard fork when the order it would
leave behind does not reproduce that settled prefix.

The measure is the ORDER, not `rev-list rem..loc`: when a
remote has already absorbed my branch, no commit of mine is
missing, yet my history can still be reordered underneath
me. `order.lua` holds only `post`/`like`/`revoke`, so the
`merge`/`state` commits a pushing peer dates via `-o now`
can never move the line.

When either threshold is crossed, the local branch REFUSES
to merge:

```
ERROR : chain sync : hard fork
```

It does not merge-and-order-itself-first: it does not
reconcile at all. The local branch is left untouched and
the remote's posts are not absorbed.

The settled prefix is built from my own order and my own
commits' timestamps, so the remote cannot inflate it.

A fast-forward is refused only if it REWRITES the settled
prefix. A remote that merely appends after my history is
accepted, even when my branch is old: entrenchment rejects
reordering, not new content. This matters because a peer
that pulls my branch and pushes it back with its own posts
spliced into my settled history arrives as a fast-forward.

Below the line nothing is protected: a young branch, or one
whose recent entries fit inside the window, is reordered by
plain consensus.

The refusal is ONE-DIRECTIONAL: it is the RECEIVER that
protects its own order. A peer that is not entrenched still
absorbs an entrenched branch by consensus, so the entrenched
side keeps broadcasting while refusing what would rewrite
its settled history.

### Branch Merge Ordering (precedence)

1. **Activity threshold** — if the result would rewrite my
   settled prefix (older than 7 days, or more than 100
   entries back), the sync is REFUSED (hard fork); nothing
   below applies
2. **Reputation** — whichever branch has more reputation in
   the common prefix is ordered first
3. **Tiebreaker** — lexicographical order of hashes

Rule 1 is evaluated ONLY at the outermost local-vs-remote
decision. Because an entrenched branch never merges, no
merge commit can encode a rule-1 decision, so replaying a
merge during validation only ever has to reproduce
`consensus` (steps 2-3).

### Stable vs Unstable Consensus

- **Stable**: entries older than the threshold are settled;
  any sync that would reorder them is refused
- **Unstable**: entries inside the window are still merged
  and may be reordered by an incoming branch

Stable consensus freezes the order progressively — the
threshold operates backward from the newest local post,
freezing older posts as permanent. This creates checkpoints
for efficient reputation caching.

### Test Coverage

| Test              | Scenario                                    | Result   |
|-------------------|---------------------------------------------|----------|
| `n03_merge_ok`    | 6 concurrent posts, no time gap             | converge |
| `n04_merge_fail`  | 101 concurrent posts per peer (>100)        | diverge  |
| `n05_merge_fail`  | 8 days apart (>7 days)                      | diverge  |
| `n05_merge_ok`    | 3 pioneers, concurrent posts, within limits | converge |

### Reference

SBSeg-23 paper: `fsantanna-no/sbseg-23` — Section on
consensus merge rules.

## Paper vs Git-Based Conflict Rejection

The original paper rejects commits from the conflicting
commit onward — earlier commits in the losing branch are
kept. Git-based merge rejects the **entire** losing branch,
including commits before the conflict. This is because git
merge operates on whole branches, not individual commits.

See [merge.md](merge.md) §3 "Paper vs Git-Based Merge" for
the full comparison.

## Pipeline Summary

```
git fetch                      — git validates objects
    |
merge-base                     — find common ancestor
    |
consensus                      — earlier first-commit
                                 wins
    |
find last state checkpoint      — walk back from
                                 merge-base to nearest
                                 state commit or genesis
    |
load checkpoint state           — git_load from
                                 checkpoint ref
    |
replay checkpoint..merge-base   — bring state up to
                                 merge-base
    |
load winner state               — checkpoint + replay
    |
validate loser commits         — replay + dry-merge
    (on fail: discard rest)      per commit
    |
build merge commit             — git commit-tree
                                 (plumbing, no git merge)
    |
commit state                   — "freechains: state"
```
