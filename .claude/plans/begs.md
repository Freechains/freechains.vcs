# Begs: BLOCKED Posts on Fan Branches

## Context

When a user posts with `--beg` (insufficient reputation
or no `--sign`), the post should not sit on main HEAD.
Otherwise, the next normal post would build on top of a
BLOCKED post, linking it into the consensus DAG.

## Design

Fan structure: each `--beg` commit forks from current
HEAD as a separate ref under `refs/begs/`.

```
       / beg.1 \
HEAD  - beg.2   > begs (refs/begs/*)
       \ beg.3 /
```

- Each beg has current HEAD as parent
- Main HEAD does NOT advance
- Begs are independent (no linear chain)
- Original signed commit preserved (no cherry-pick)

### Beg Branch Structure

A beg branch is either:
1. A single beg commit (pending)
2. A beg commit followed by a like-to-self (ready
   to merge)

The like-to-self is the unblock condition. Someone
with reps likes the beg post, and that like commit
is appended to the beg branch. Then the beg branch
merges into main.

### Unblock Flow

```
     / beg.1 - like.1 ---\
xxx                        > new HEAD (merge)
     \ - commits - head -/
```

1. `beg.1` — blocked post (on refs/begs/)
2. `like.1` — like targeting beg.1 (appended to beg
   branch, signed by someone with reps)
3. Merge: beg branch tip (like.1) merges into main
4. Merge has two parents: main HEAD + like.1
5. Original beg commit preserved as ancestor of like.1

## Post Entry in posts.lua

Two cases for `--beg`:

| Case              | Entry                                         |
|-------------------|-----------------------------------------------|
| `--beg` only      | `{ blocked=true, reps=0 }`                    |
| `--beg --sign`    | `{ blocked=true, author=ARGS.sign, reps=0 }`  |

Time effects: tracked but frozen until unblocked.
When `--beg --sign`:
- `time` and `state` fields present but not processed
  during discount/consolidation scans
- On unblock: time tracking activates

## Git Implementation

### Creating a beg commit

```bash
# 1. Stage files normally
git -C REPO add <files>

# 2. Commit on current HEAD
git -C REPO commit [signing flags] \
    --trailer 'freechains: post' -m '<msg>'

# 3. Get the new commit hash
BEG=$(git -C REPO rev-parse HEAD)

# 4. Store as ref under refs/begs/
git -C REPO update-ref refs/begs/$NOW-$BLOB8 HEAD

# 5. Reset main back (HEAD was advanced by commit)
git -C REPO reset --hard HEAD~1
```

The beg commit is only reachable via `refs/begs/$NOW-$BLOB8`.

### Liking a beg post (unblock trigger)

The like targets a beg post. The like commit must be
appended to the beg branch, not to main:

```bash
# 1. Switch to the beg branch
git -C REPO checkout refs/begs/$NOW-$BLOB8

# 2. Create like commit (on detached HEAD = beg tip)
git -C REPO add <like files>
git -C REPO commit -S --trailer 'freechains: like' ...

# 3. Update the beg ref to new tip
git -C REPO update-ref refs/begs/$NOW-$BLOB8 HEAD

# 4. Merge beg branch into main
git -C REPO checkout main
git -C REPO merge refs/begs/$NOW-$BLOB8

# 5. Clean up ref
git -C REPO update-ref -d refs/begs/$NOW-$BLOB8
```

### Listing begs

```bash
git -C REPO for-each-ref refs/begs/ \
    --format='%(refname:short) %(objectname)'
```

## Files to Modify

| File                          | Changes                           |
|-------------------------------|-----------------------------------|
| `src/freechains/chain.lua`    | Beg commit: update-ref + reset    |
| `src/freechains/chain.lua`    | Like: detect beg target, branch   |
| `src/freechains/chain.lua`    | Merge beg into main after like    |
| `src/freechains/chain.lua`    | posts.lua: blocked field          |
| `src/freechains/chain.lua`    | Stage: skip blocked entries       |
| `src/freechains.lua`          | (--beg flag already added)        |
| `tst/cli-reps.lua`            | Gate tests: beg on ref            |
| `tst/cli-sign.lua`            | Beg test: not on HEAD             |

## Implementation Steps

### 1. Beg commit flow

In chain.lua, after the normal commit:
- If `ARGS.beg`: store commit as `refs/begs/$NOW-$BLOB8`,
  reset HEAD back
- Add `blocked=true` to posts.lua entry
- If `ARGS.sign`: include author field
- Print the beg commit hash (not HEAD)

### 2. Stage: skip blocked entries

In discount/consolidation scans, skip entries where
`blocked == true`. They don't participate in time
effects until unblocked.

### 3. Like targeting a beg post

When a like targets a post that is in `refs/begs/`:
- Checkout the beg branch (detached HEAD)
- Append the like commit
- Update the beg ref
- Merge beg branch into main
- Remove `blocked=true` from posts.lua
- Activate time tracking
- Clean up the beg ref

### 4. Tests

- `--beg` post not on HEAD (HEAD unchanged)
- `--beg` post reachable via `refs/begs/`
- `--beg` post has `blocked=true` in posts.lua
- Like a beg: like appended to beg branch
- Like a beg: merged into main
- Like a beg: `blocked` removed from posts.lua
- Stage skips blocked entries

## Resolved Questions

1. **Trailer:** `freechains: post` — a beg is immutable
   and eventually becomes a regular post.
2. **Ref name:** `refs/begs/<timestamp>-<blob8>` —
   same pattern as like filenames. Unique, sortable.
3. **Merge commit:** unsigned — the merge is mechanical,
   triggered by the signed like.
4. **Multiple likes:** first like triggers merge
   immediately. No accumulation.
5. **Liker can't afford:** normal like validation applies,
   error returned, beg stays pending.

## TODO

- [ ] Impl: beg commit → refs/begs/ + reset HEAD
- [ ] Impl: posts.lua blocked field
- [ ] Impl: stage skips blocked entries
- [ ] Impl: like beg → append to beg branch + merge
- [ ] Impl: remove blocked field on unblock
- [ ] Tests: beg not on HEAD
- [ ] Tests: beg reachable via ref
- [ ] Tests: like beg triggers merge
- [ ] Tests: blocked removed after merge
