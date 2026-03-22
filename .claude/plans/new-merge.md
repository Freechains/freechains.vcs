# New Merge Design

## 1. State Directory

State files move from `.freechains/` to `.freechains/state/`:

| File        | Old path                    | New path                          |
|-------------|-----------------------------|-----------------------------------|
| authors.lua | `.freechains/authors.lua`   | `.freechains/state/authors.lua`   |
| posts.lua   | `.freechains/posts.lua`     | `.freechains/state/posts.lua`     |
| now.lua     | `.freechains/now.lua`       | `.freechains/state/now.lua`       |
| order.lua   | (new)                       | `.freechains/state/order.lua`     |

Key changes:
- `now.lua` is now **committed** to git (was excluded before)
- `now.lua` mimics the behavior of authors/posts in all cases
- `G` table gains `G.now` field
- `now.lua` is always written (no dirty flag needed, time
  always advances)
- Remove `now.lua` from `.git/info/exclude`
- `order.lua` is new: stores the deterministic total order
  of commits as computed by consensus/replay
- `G` table gains `G.order` field

### Skeleton

Skel updated to match:

| Old                            | New                                  |
|--------------------------------|--------------------------------------|
| `skel/.freechains/authors.lua` | `skel/.freechains/state/authors.lua` |
| `skel/.freechains/posts.lua`   | `skel/.freechains/state/posts.lua`   |
| `skel/.freechains/now.lua`     | `skel/.freechains/state/now.lua`     |
| (new)                          | `skel/.freechains/state/order.lua`   |

Skel exclude: remove `now.lua` line.

## 2. When State Files Change vs Commit

| Event              | Disk write                | Git commit                         |
|--------------------|---------------------------|------------------------------------|
| Genesis (config)   | authors, posts, now, order | authors, posts, now, order (state) |
| Clone              | authors, posts, now, order | none                               |
| Post/like          | authors, posts, now, order | never                              |
| Sync recv (non-ff) | authors, posts, now, order | authors, posts, now, order (state) |

- Post/like commits contain only content + trailer, never
  state files
- State commits happen at genesis, before sync (on state
  branch), and after non-ff merge
- `now.lua` value at genesis: `NOW.s` (not 0)

## 3. Commit Types

Trailers used with `Freechains:` key:

| Trailer              | Meaning                          |
|----------------------|----------------------------------|
| `Freechains: state`  | genesis or post-merge checkpoint |
| `Freechains: post`   | post commit                      |
| `Freechains: like`   | like commit                      |
| (no trailer)         | git merge commit                 |

### DAG Diagram (divergence + sync)

```
[state]  genesis
   |
[post]   post by Alice
   |
[like]   like on Alice's post
   |
[post]   post by Bob
   |
[post]   post by Alice  <-- local HEAD before sync
   |
   |        [post]  post by Carol  <-- FETCH_HEAD
   |        /
   |       /
[merge]   git merge (no trailer)
   |
[state]   state commit (state/authors + state/posts
          + state/now written)
```

### Fast-forward case (no divergence)

```
[state]  genesis
   |
[post]   post by Alice  <-- local HEAD
   |
[post]   post by Bob    <-- FETCH_HEAD (remote ahead)
```

No merge, no state commit -- local just advances.

### Properties

- `[state]` only appears at genesis and immediately after a
  non-ff merge
- `[merge]` is a raw git merge, no freechains trailer
- Between any two `[state]` commits the path is linear (no
  forks) -- linearity guarantee
- `[post]` and `[like]` never include state files

## 4. Commit Types (with state branch)

### Non-ff merge (state branches)

```
[state]  genesis
   |
[post]   post by Alice
   |
[post]   post by Bob
   |
[state]  local checkpoint (L)
   |
   |        [post]   post by Carol
   |        |
   |        [state]  remote checkpoint (R)
   |        /
   |       /
[merge]   git merge (no trailer)
   |
[state]   merged state commit
```

After merge: `main` and `state` both point to `[state]`
at tip.

### Fast-forward

```
Before:
main:   [state]gen -- [post]A
state:  [state]gen -- [post]A -- [state]L

After:
main:   [state]gen -- [post]A -- [post]B
state:  [state]gen -- [post]A -- [post]B -- [state]R
```

- `main` advances to last post (B), not to state commit
- `state` adopts remote tip (R)
- Local state commit L is discarded

### Branch pointer summary

| Scenario  | main points to   | state points to  |
|-----------|------------------|------------------|
| Genesis   | state commit     | same as main     |
| Post/like | post/like commit | unchanged        |
| Pre-sync  | unchanged        | amend: main + st |
| FF sync   | last post commit | remote state tip |
| Non-ff    | new state commit | same as main     |

## 5. State Branch

Sync operates on a `state` branch, not `main`.

### State branch lifecycle

- **Genesis**: creates initial commit on `main`, which is
  also a state commit. `state` branch starts here.
- **Post/like**: commits to `main` only. `state` branch
  unchanged.
- **Before sync (send or recv)**: commit current disk state
  to `state` branch (amend on top of `main` HEAD).
  Reset `state` to `main`, write state files, amend.
- **Sync**: fetch/push operates on `state` branch.
- **After merge**: `main` advances to match `state`.

### DAG (state branch sync)

```
LOCAL:
main:   [state]gen -- [post]A -- [post]B
state:  [state]gen -- [post]A -- [post]B -- [state]L

REMOTE:
state:  [state]gen -- [post]C -- [state]R

AFTER RECV (merge on state branches):

state:  ...--[post]B --[state]L --[merge]--[state]new
                                  /
        ...--[post]C --[state]R --

main:   advanced to match state
```

### State loading (no replay for checkpoints)

| What                       | Old (walk + replay)         | New (direct load)   |
|----------------------------|-----------------------------|---------------------|
| State at merge-base        | walk back, find checkpoint, replay forward | load from merge-base state files |
| State at local tip         | replay from merge-base      | load from L's state files |
| State at remote tip        | deep-copy G_com, replay     | load from R's state files |
| Loser replay on winner     | still needed                | still needed        |

### Merge flow

1. Load `G_winner` from winner's state commit
2. Replay loser's posts/likes (merge-base to loser
   tip, excluding state commit) on top of `G_winner`
3. Result is the merged state
4. Commit merged state as new state commit
5. Advance `main` to match `state`

### Open question (answered: yes, G_com is needed)

`G_com` is needed for `branch_compare` — it provides
the prefix reputation used to determine the winner.

## 6. Consensus

### 6.1. Validation & Consensus

#### 6.1.1. Validation

Validation checks that each commit in a branch is
"legal" against the ongoing state:
- **Reputation thresholds**: author has enough reps
- **File-op costs**: author can afford the operations
- **Merge compatibility**: commit merges cleanly with
  winner's tree (dry-merge per commit)
- **Genesis immutability**: genesis.lua never changes

On first validation failure: discard that commit and
all subsequent commits in the branch.

**When validation runs:**
- **Remote branch**: validated first, before consensus.
  Uses `G_com` + replay remote commits one by one.
- **Loser branch**: validated during replay on top of
  winner's state.

Validation and consensus cannot be separated — they
are interleaved. Validation mutates `G` during replay,
and `branch_compare` depends on `G`. A discarded
commit changes the ongoing state, which can affect
nested `branch_compare` results.

#### 6.1.2. branch_compare

```lua
-- Returns winner_hash, loser_hash
-- G:     ongoing state at the fork point (live table)
-- left:  left tip state commit hash
-- right: right tip state commit hash
local function branch_compare (G, left, right)
```

##### Algorithm

1. Collect author sets from git log of each branch
   (signing keys)
2. Sum prefix reps from `G` for each author set
3. Higher sum wins -> return that hash first
4. Tie -> hash tiebreaker (lexicographic)

##### Author collection rules

- **Posts (signed)**: signer key counts
- **Posts (unsigned/beg)**: skipped (no key)
- **Likes**: signer key counts (not the target)
- **State commits**: skipped (both common and tips)
- An author in **both** branches counts for both sums

### 6.2. Nested merge scenario

When local history already contains a previous merge,
`branch_compare` must handle the full DAG reachable
from each tip.

```
[state]  genesis (G)
   |
[post]   P1 by Alice
   |
[state]  S1
   |
   |        [post]   P2 by Bob
   |        |
   |        [state]  S2
   |        /
   |       /
[merge]   M1 (first merge, local history)
   |
[state]   S3
   |
[post]    P3 by Carol
   |
[state]   S4 (local tip)
   |
   |        [post]   P4 by Dave
   |        |
   |        [state]  S5 (remote tip)
   |        /
   |       /
[merge]   M2 (new merge)
   |
[state]   S6
```

Merge-base of S4 and S5 is G (genesis).

Range `G..S4` includes: P1, S1, P2, S2, M1, S3, P3,
S4. Git log walks into M1's second parent, so P2 and
S2 are reachable.

Author sets for `branch_compare(G, S4, S5)`:
- Local (G..S4): Alice (P1), Bob (P2), Carol (P3)
- Remote (G..S5): Dave (P4)

State commits (S1-S5) and merge commit (M1) are
skipped when collecting authors. The full DAG between
merge-base and each tip is walked, including content
merged in by previous merges.

### 6.3. Recursive replay

#### Updated signature

```lua
-- G:     ongoing state at the fork point (live table,
--        not loaded from a commit)
-- left:  left tip state commit hash
-- right: right tip state commit hash
local function branch_compare (G, left, right)
```

The first argument is the ongoing `G` table, not a
commit hash. This is because during replay, the state
at a fork point may differ from what was stored at
the original merge-base commit.

#### Why nested consensus can change

In the 6.2 scenario, suppose Dave's branch (remote)
wins at M2 level. The loser (local, G..S4) is replayed
on top of Dave's state. When the replay reaches M1's
fork point, the ongoing `G` includes Dave's effects.
Prefix reps are different from when M1 was originally
created -> `branch_compare` may pick a different
winner for M1's sub-branches.

Therefore S3 (the stored state after M1) cannot be
reused as a checkpoint. The nested merge must be
fully re-evaluated.

#### Replay algorithm (recursive)

1. Replay loser branch from merge-base to loser tip
2. When a merge commit (M1) is encountered:
   a. Find M1's two parents and their merge-base
   b. Run `branch_compare(G_ongoing, parent1, parent2)`
      with the current live state
   c. Replay M1's loser on M1's winner (recurse —
      deeper merges may exist)
   d. Continue replay after M1
3. Only the **top-level winner** state is loaded
   directly (no replay needed). All loser branches
   require full recursive replay.

#### order.lua reliability

`order.lua` in a nested state commit (e.g. S3 after
M1) is only reliable without an outer branch/consensus.
When replayed as a loser, the outer context changes
`G`, so `branch_compare` may produce a different order.
Only the **top-level winner's** `order.lua` is
reliable.

#### What changed vs old design

| Aspect              | Old                    | New                    |
|---------------------|------------------------|------------------------|
| branch_compare arg  | commit hash (G_com)    | live G table           |
| Nested consensus    | immutable (reuse S3)   | re-evaluated (may change) |
| Checkpoint reuse    | yes (state commits)    | only for top-level winner |
| collect/replay      | needed for loser       | still needed, recursive |

### 6.4. Validation failure propagation

#### Remote validation fails

If the remote branch fails validation (using G_com +
replay), the remote is ignored entirely and added to
a blacklist. No merge happens.

#### Loser replay failure

During loser replay on top of winner's state, if a
commit fails validation, that commit and all subsequent
commits in the branch are discarded.

Example:

```
Common state: Bob has 1 rep, Alice has 10 rep

Winner branch: Alice dislikes Bob -> Bob has 0 rep

Loser branch:  L1 (Bob posts, costs 1 rep)
               L2 (Bob posts)
               L3 (Carol posts)

Original context: Bob had 1 rep -> L1 valid
Winner's state:   Bob has 0 rep -> L1 fails

L1 fails -> L1, L2, L3 all discarded.
Carol's L3 is collateral damage.
```

The loser branch was valid in its original context.
Failure happens because the winner's state changed
the reps (e.g., a dislike reduced Bob's reps).

#### Nested failure

In recursive replay, a validation failure inside a
nested merge (M1) changes G_ongoing. This can affect
`branch_compare` for subsequent merges in the same
branch, altering nested consensus ordering. But it
cannot change the top-level winner/loser decision —
`branch_compare` at the outer level runs before any
replay/validation.

#### Validation cannot change the winner

`branch_compare(G, left, right)` runs before replay.
It uses `G` and author sets from the DAG (immutable).
The winner/loser decision is locked in before
validation begins. Validation only affects nested
consensus within the loser's replay.
