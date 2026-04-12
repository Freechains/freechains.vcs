# New Merge Design

## Implementation Progress

| Step | Section | Status |
|------|---------|--------|
| 1 | State directory | [x] done |
| 2 | apply + time_effects | [x] done |
| 3 | Validation inside apply | [x] done (partial) |
| 4 | Consensus / branch_compare | [ ] pending |
| 5 | State branch | [ ] pending |
| 6 | Unified merge pipeline | [ ] pending |

### Step 1: State directory (done)
- [x] Moved skel files to `state/` subdir
- [x] Added `order.lua` to skel
- [x] Removed `now.lua` from `.git/info/exclude`
- [x] Updated all paths in src/ and tst/
- [x] Removed redundant clone writes (git clone
  already has genesis files)

### Step 2: apply + time_effects (done)
- [x] Moved time_effects from `init.lua` into `apply`
- [x] `apply(G, nil)` for time_effects only (reps path)
- [x] `G.now` field loaded/written
- [x] Sync loads `now` from state commit (not hardcoded)

### Step 3: Validation inside apply (done, partial)
- [x] Post: `reps <= 0` → "insufficient reputation"
- [x] Like: `reps <= 0` → "insufficient reputation"
- [x] Like: `not sign` → "unsigned"
- [x] Like: `num == 0` → "expected positive integer"
- [x] Like: invalid target → "target must be..."
- [x] Like: post not found in G.posts
- [x] post.lua: revert commit on apply failure
- [x] post.lua: restore state files after revert
- [x] post.lua: beg + auth gate stays (pre-commit)
- [x] post.lua: like `--sign` gate stays (pre-commit)
- [x] Tests refactored to `_, Q, err` format
- [x] Added missing `like-zero-number` test

### Pending issues
- [x] ~~Sync test Step 3 failure~~: resolved, step 3
  passes (bit-equal diff between peers).
- [ ] Like replay not integrated in sync.lua
  (`error "TODO: replay likes via apply"`).
  Design exists in rec-replay.md (diff-tree + git show).

### Step 4: Consensus / prefix reps (pending)
- [ ] Replace timestamp comparison with prefix reps
- [ ] Load G_a, G_b from tip state commits
- [ ] Sum G_com.authors[key].reps for authors in each tip
- [ ] Higher sum wins, hash tiebreaker (smaller wins)
- [ ] No commit traversal — state tables only

### Step 5: State branch (pending)
- [ ] Create `state` branch at genesis
- [ ] Pre-sync: commit state to `state` branch
- [ ] Sync operates on `state` branch

### Step 6: Unified merge pipeline (pending)
- [ ] Rewrite sync recv (FF + non-FF)
- [ ] Recursive replay for nested merges
- [ ] State loading from state commits (no walk+replay)

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

#### order.lua format

Flat list of commit hashes in consensus order:

```lua
return {
    "abc123",  -- genesis (state)
    "def456",  -- post
    "ghi789",  -- like
    "jkl012",  -- merge
    "mno345",  -- state
}
```

- Includes all commit types: genesis, posts, likes,
  merges, state commits
- Discarded commits (validation failure) are absent
- Recomputed on every state change (like authors/posts)

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

## 3. apply: validation + state mutation

Unified function for processing one entry (post or
like). Used by both local commands and sync replay.

```lua
-- Returns true on success, false+err on failure
function apply (G, entry)
    time_effects(G, entry.time)
    -- validate
    -- if invalid: return false, "error message"
    -- mutate G
    -- return true
end
```

### Time effects (inside apply)

Before processing each entry, apply runs discount
and consolidation scans at `entry.time`:
- **Discount scan**: posts in "00-12" state, refund
  if discount period elapsed
- **Consolidation scan**: posts in "12-24" state,
  grant +1 rep if 24h slot open
- **Cap**: clamp all authors at max

`entry.time` is `NOW.s` for local commands and the
commit's author timestamp during replay.

### Validation checks

- **Post (signed)**: author has enough reps (rule 4.a),
  file-op cost affordable (rule 5)
- **Like**: liker has enough reps, target post exists
- **Beg**: does not go through apply. Handled
  separately by local code only. Never appears in
  replay.

### On failure

Returns `false, "error message"`. Caller decides
the consequence:
- **Local command**: report error to user
- **Sync (remote validation)**: ignore remote,
  blacklist
- **Sync (loser replay)**: discard this commit and
  all subsequent

### State mutation (on success)

Same as current apply logic:
- **Post**: set G.posts[hash], deduct reps from author
- **Like**: deduct from liker, tax, split to target
- **Cap**: clamp all authors at max
- **Order**: append commit hash to G.order

## 4. Commit Types

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

## 5. Commit Types (with state branch)

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

## 6. State Branch

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

## 7. Consensus

### 7.1. Validation & Consensus

#### 7.1.1. Validation

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

#### 7.1.2. consensus (prefix reps)

```lua
-- Returns winner_hash, loser_hash
-- G_com: state at the merge-base (prefix reps)
-- com:   merge-base commit hash
-- a:     left tip commit hash
-- b:     right tip commit hash
local function consensus (G_com, com, a, b)
```

##### Algorithm

1. Load G_a.authors from tip a state files
2. Load G_b.authors from tip b state files
3. Sum G_com.authors[key].reps for each key in
   G_a.authors (0 if absent in G_com)
4. Sum G_com.authors[key].reps for each key in
   G_b.authors (0 if absent in G_com)
5. Higher sum wins -> return that hash first
6. Tie -> hash tiebreaker (smaller wins)

##### Rationale (no commit traversal)

G_com is already consolidated (time_effects applied).
The authors table at each tip contains exactly the
authors who participated on that branch (or were
inherited from the common prefix). Their prefix reps
in G_com reflect their standing before the fork.
No need to traverse commits with git log + ssh.verify.

### 7.2. Nested merge scenario

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

### 7.3. Recursive replay (NOT YET — future scope)

Recursive replay is deferred. Current implementation
handles only top-level consensus (no nested merges).

When implemented, the `consensus()` function signature
will change to accept a live G table instead of G_com,
so nested merges can re-evaluate with ongoing state.
See rec-replay.md for the full design.

### 7.4. Validation failure propagation

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

#### Fast-forward validation

FF is not a shortcut — remote commits are validated
even when no divergence exists.

1. Detect FF (local is ancestor of remote)
2. Validate remote commits (local state + replay,
   one by one)
3. If any fails -> ignore remote, blacklist
4. If all pass -> advance `main` to last post,
   `state` to remote tip

FF and non-FF both validate the remote first. The
difference: FF has no merge/consensus step after
validation.

Remote's `order.lua` is adopted directly in FF
(no outer context to invalidate it, no recomputation
needed).

## 8. Unified Merge Pipeline

### Recv (non-FF)

1. Commit local state to `state` branch
   (reset to main, write state files, amend)
2. `git fetch` remote `state`
3. Merge-base between local state and remote state
4. Detect FF or non-FF

5. Load G_com from merge-base state files
6. Validate remote: replay remote commits on G_com
   via apply. Any failure -> blacklist, stop.
7. `consensus(G_com, com, loc, rem)` -> winner, loser
   (loads G_a, G_b from tip state files, sums prefix
   reps, higher wins, hash tiebreaker)
8. Load G_winner from winner's state commit
9. Replay loser commits on G_winner via apply
    Failures -> discard commit + subsequent
11. `git merge`
12. Append merge + state commit hashes to G.order
13. Write state files (authors, posts, now, order)
14. Commit state (trailer: Freechains: state)
15. Advance `main` to match `state`

### Recv (FF)

1. Commit local state to `state` branch
2. `git fetch` remote `state`
3. Detect FF (local is ancestor of remote)

4. Load G_loc from local state files
5. Validate remote commits (local_tip..remote_tip)
   via apply on G_loc.
   Any failure -> blacklist, stop.
6. Assert replayed state matches remote's committed
   state files
7. Advance `main` to last post commit
8. Advance `state` to remote tip
9. Write replayed state to disk

### Send

1. Commit local state to `state` branch
   (reset to main, write state files, amend)
2. `git push` remote `state`
