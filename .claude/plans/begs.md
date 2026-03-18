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

## repl-begs vs repl-head: What Differs

### Summary

| Aspect      | head                   | begs                            |
|-------------|------------------------|---------------------------------|
| Genesis     | `GEN_1`                | `GEN_0`                        |
| Post flag   | `--sign KEY`           | `--beg --sign KEY`             |
| Destination | HEAD                   | `refs/begs/<id>`               |
| Counting    | `rev-list --count HEAD`| `for-each-ref refs/begs/`      |
| Fetch       | `git fetch <src> <br>` | `git fetch <src> refs/begs/*`  |
| Merge       | `git merge FETCH_HEAD` | `git merge <ref>` (per beg)    |

### Section-by-section

**1. Host A: create chain + post/beg**

| head                              | begs                            |
|-----------------------------------|---------------------------------|
| GEN_1                             | GEN_0                           |
| `--sign KEY`                      | `--beg --sign KEY`              |
| post on HEAD, count = 2           | beg on refs/begs/, HEAD = 1     |
| assert count                      | assert beg ref exists           |

**2. Host B: clone + post/beg**

| head                              | begs                            |
|-----------------------------------|---------------------------------|
| clone gets genesis + A's post     | clone gets genesis only         |
| B has 2 commits                   | B has 1 commit (genesis)        |
| (no extra fetch needed)           | fetch `refs/begs/*` from A      |
|                                   | verify A's beg ref arrived      |
| B posts (--sign KEY), count = 3   | B begs (--beg --sign KEY)       |
| assert count                      | assert beg ref exists           |

**3. Host A: fetch from B + merge**

| head                              | begs                            |
|-----------------------------------|---------------------------------|
| fetch branch from B               | fetch `refs/begs/*` from B      |
| dry-run merge FETCH_HEAD          | count total beg refs (A's + B's)|
| merge FETCH_HEAD (fast-forward)   | merge ref1 into HEAD (ff)       |
| count = 3                         | merge ref2 into HEAD (true)     |
| both files present, A == B        | both files present              |

**4. Bidirectional sync**

| head                              | begs                            |
|-----------------------------------|---------------------------------|
| both post (--sign KEY)            | both beg (--beg --sign KEY)     |
| A fetches B branch + merge        | A fetches refs/begs/* from B    |
| B fetches A branch + merge        | B fetches refs/begs/* from A    |
| both count = 6, A == B            | verify same beg refs both sides |

**5. Unrelated histories**

| head                              | begs                            |
|-----------------------------------|---------------------------------|
| C creates chain with GEN_1        | C creates chain with GEN_0      |
| C fetches A's branch              | C fetches refs/begs/* from A    |
| dry-run merge fails               | merge beg ref into C fails      |

**6. Conflict**

| head                              | begs                            |
|-----------------------------------|---------------------------------|
| A and B post to log.txt           | reset env, re-create chains     |
| fetch branch, dry-run fails       | A and B beg to log.txt          |
| merge fails, conflict markers     | fetch refs/begs/* from B        |
| abort restores clean state        | merge ref1 (ff, ok)             |
|                                   | merge ref2 -> conflict          |
|                                   | conflict markers, abort restores|

### Local vs Remote

Only difference is the transport layer:

| Aspect       | local              | remote                    |
|--------------|--------------------|---------------------------|
| mkdir        | `ROOT_{A,B,C}`     | `ROOT/chains`             |
| daemon       | none               | git daemon per host       |
| fetch source | `REPO_A` (path)    | `URL_A .. "test/"` (git)  |
| clone source | `REPO_A` (path)    | `URL_A .. "test/"` (git)  |

## cli-post vs cli-begs: What Differs

### cli-post (signed posts on HEAD)

1. POST FILE: copy, content, genesis, update, second
2. POST INLINE: auto-name, --file creates/appends
3. POST --why: commit message
4. POST errors: nonexistent chain

All posts go on HEAD, are signed, advance commit
history.

### cli-begs (blocked posts on refs/begs/)

1. SIMPLE BEG: refs/begs/ created, HEAD unchanged,
   blocked in posts.lua
2. MULTIPLE BEGS: same HEAD, different HEADs, ref count
3. LIKES ON BEGS: merge into HEAD, unblock, ref removed,
   insufficient reps rejected, self-like rejected
4. MERGE STRUCTURE: 2 parents, sig intact, HEAD advances

### Shared between both

- Inline posting (auto-name, content)
- File posting (--file)
- --why commit message
- Same post creation code path; destination differs

### Unique to cli-begs

- `refs/begs/` ref creation and HEAD not advancing
- `state = "blocked"` in posts.lua
- Like-triggered merge (beg + HEAD -> merge commit)
- Ref removed after merge
- Insufficient reps to like
- Self-like with 0 reps rejected

### Known bugs in cli-begs.lua

- Lines 43, 174: reads `.freechains/posts.lua` but
  should be `.freechains/local/posts.lua`
  (tracked file doesn't exist; local state is in local/)

## Implementation Steps

### Step 1: Read and understand

Read all files side by side:
- `tst/repl-local-head.lua` vs `tst/repl-local-begs.lua`
- `tst/repl-remote-head.lua` vs `tst/repl-remote-begs.lua`
- `tst/cli-post.lua` vs `tst/cli-begs.lua`

For each pair, note what's shared and what differs.
Compare against the tables above.

### Step 2: Fix cli-begs.lua

- Fix path: `.freechains/posts.lua` ->
  `.freechains/local/posts.lua` (lines 43, 174)
- Depends on: author-hash.md (--sign required for begs)

### Step 3: Write repl-local-begs.lua

Start from repl-local-head.lua structure.
Apply section-by-section adaptations above.
Key changes:
- GEN_1 -> GEN_0
- `--sign KEY` -> `--beg --sign KEY`
- Branch fetch -> `refs/begs/*` fetch
- HEAD merge -> per-ref merge
- Commit counting -> ref counting

### Step 4: Write repl-remote-begs.lua

Same adaptations as Step 3, but with:
- git daemon setup (ports, PIDs, start/stop)
- git:// URLs instead of local paths
- Beg ref fetch over git:// protocol

### Step 5: Compare against main

```
git diff main -- tst/repl-local-begs.lua
git diff main -- tst/repl-remote-begs.lua
git diff main -- tst/cli-begs.lua
```

Review: are all adaptations correct and minimal?

### Step 6: Run tests

```
lua5.4 tst/repl-local-begs.lua
lua5.4 tst/repl-remote-begs.lua
lua5.4 tst/cli-begs.lua
```

Fix any failures.

## Dependencies

- None. Independent of author-hash.md.

## Done

- [x] Write failing tests (cli-begs.lua)
- [x] Impl: beg commit -> refs/begs/ + reset HEAD
- [x] Impl: posts.lua state="blocked" field
- [x] Impl: stage skips blocked entries
- [x] cli-post.lua adapted (GEN_1, --sign KEY)
- [x] cli-sign.lua beg section (checks by hash)
- [x] cli-now.lua adapted (--sign KEY)
- [x] repl-local-begs.lua (refs/begs/* mechanism)

## TODO

- [x] Step 2: Fix cli-begs.lua (local/posts.lua path)
- [x] Step 3: Fix repl-local-begs.lua (exec true flags, clean assert)
- [x] Step 4: Write repl-remote-begs.lua (refs/begs/* mechanism)
- [ ] Step 5: Compare against main
- [x] Step 6: Run tests (all pass)
- [ ] Impl: like beg -> append to beg branch + merge
- [ ] Impl: remove blocked field on unblock
