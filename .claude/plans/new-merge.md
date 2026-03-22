# New Merge Design

## 1. State Directory

State files move from `.freechains/` to `.freechains/state/`:

| File        | Old path                    | New path                          |
|-------------|-----------------------------|-----------------------------------|
| authors.lua | `.freechains/authors.lua`   | `.freechains/state/authors.lua`   |
| posts.lua   | `.freechains/posts.lua`     | `.freechains/state/posts.lua`     |
| now.lua     | `.freechains/now.lua`       | `.freechains/state/now.lua`       |

Key changes:
- `now.lua` is now **committed** to git (was excluded before)
- `now.lua` mimics the behavior of authors/posts in all cases
- `G` table gains `G.now` field
- `now.lua` is always written (no dirty flag needed, time
  always advances)
- Remove `now.lua` from `.git/info/exclude`

### Skeleton

Skel updated to match:

| Old                            | New                                  |
|--------------------------------|--------------------------------------|
| `skel/.freechains/authors.lua` | `skel/.freechains/state/authors.lua` |
| `skel/.freechains/posts.lua`   | `skel/.freechains/state/posts.lua`   |
| `skel/.freechains/now.lua`     | `skel/.freechains/state/now.lua`     |

Skel exclude: remove `now.lua` line.

## 2. When State Files Change vs Commit

| Event              | Disk write         | Git commit         |
|--------------------|--------------------|--------------------|
| Genesis (config)   | authors, posts, now | authors, posts, now (state commit) |
| Clone              | authors, posts, now | none               |
| Post/like          | authors, posts, now | never              |
| Sync recv (non-ff) | authors, posts, now | authors, posts, now (state commit) |

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

### Open question

Is `G_com` (state at merge-base) needed at all? E.g.
for consensus decision (reputation comparison), or can
we work with only `G_winner` + loser commit list?
