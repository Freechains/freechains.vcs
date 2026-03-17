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

The beg commit is only reachable via
`refs/begs/$NOW-$BLOB8`.

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

## Files to Modify

| File                          | Changes                           |
|-------------------------------|-----------------------------------|
| `src/freechains/chain.lua`    | Beg commit: update-ref + reset    |
| `src/freechains/chain.lua`    | Like: detect beg target, branch   |
| `src/freechains/chain.lua`    | Merge beg into main after like    |
| `src/freechains/chain.lua`    | posts.lua: blocked field          |
| `src/freechains/chain.lua`    | Stage: skip blocked entries       |
| `src/freechains.lua`          | (--beg flag already added)        |
| `tst/cli-begs.lua`            | New test file                     |

## Test Plan (cli-begs.lua)

Uses `GEN_1P` (KEY=30 reps, KEY2/KEY3=0 reps).

### 1. Simple beg

- `beg-post-succeeds`: KEY2 posts with `--beg --sign`,
  returns 40-char hash, exit 0
- `beg-not-on-head`: HEAD unchanged after beg
- `beg-on-ref`: commit reachable via `refs/begs/`
- `beg-blocked-in-posts`: posts.lua has `blocked=true`

### 2. Multiple begs from HEAD

- `beg-multiple-from-head`: KEY2 and KEY3 both beg
  from same HEAD. Two refs/begs/. HEAD unchanged.
- `beg-refs-count`: `for-each-ref refs/begs/` returns 2

### 3. Multiple begs from different heads

- KEY posts (advances HEAD), KEY2 begs
- KEY posts again (advances HEAD), KEY3 begs
- `beg-different-parents`: each beg has different
  parent (verified via `git log --format=%P`)

### 4. Likes on begs

- `like-beg-succeeds`: KEY likes beg (has reps), exit 0
- `like-beg-merges`: beg merged into main, HEAD advanced
- `like-beg-unblocks`: `blocked` removed from posts.lua
- `like-beg-ref-removed`: ref gone after merge
- `like-beg-insufficient-reps`: KEY3 (0 reps) likes
  beg → error
- `like-beg-self-no-reps`: KEY2 (beggar) likes own
  beg → error

### 5. Merge structure

- `merge-two-parents`: merge commit has 2 parents
- `merge-preserves-sig`: beg commit GPG sig intact
- `merge-head-advances`: HEAD is merge commit

## TODO

- [x] Write failing tests (cli-begs.lua)
- [x] Impl: beg commit → refs/begs/ + reset HEAD
- [x] Impl: posts.lua state="blocked" field
- [x] Impl: stage skips blocked entries (free: scans match "00-12"/"12-24" only)
- [ ] Impl: like beg → append to beg branch + merge
- [ ] Impl: remove blocked field on unblock
- [ ] Tests pass

## Done so far

### Implementation (src/freechains/chain.lua)
- After commit: if `ARGS.beg`, `update-ref refs/begs/<ts>-<blob8> HEAD` + `reset --hard HEAD~1`
- Metadata: `if ARGS.beg` → `state='blocked'`, no cost deduction; else → `state='00-12'`, normal cost
- Removed outer `if ARGS.sign` wrapper on metadata block (unsigned begs get `author=nil`)
- `--beg` only on `post` subcommand (argparse enforces, no runtime check needed)

### Test files adapted for beg behavior
- `tst/cli-begs.lua` — new, 5 sections (simple beg, multiple, different heads, likes, merge structure)
- `tst/cli-post.lua` — `GEN` → `GEN_1P`, `--beg` → `--sign KEY`, `EXE` → `ENV_EXE`
- `tst/cli-sign.lua` — beg section checks commit by hash, not HEAD
- `tst/cli-now.lua` — `--beg` → `--sign KEY`, `EXE` → `ENV_EXE`
- `tst/repl-local-begs.lua` — new, beg replication via `refs/begs/*` (fetch, merge, unrelated, conflict)
- `tst/repl-local-head.lua` — needs `--beg` → `--sign KEY` (not yet done)

### Remaining work
1. **Step 4**: like beg → checkout beg ref, commit like, update-ref, checkout main, merge, delete ref
2. **Step 5**: on unblock, change `state='blocked'` → `state='00-12'` + set time + deduct cost
3. **repl-local-head.lua**: switch to `GEN_1P` + `--sign KEY`
4. **repl-remote-*.lua**: same split as local (head vs begs)
