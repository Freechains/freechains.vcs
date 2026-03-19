# Plan: freechains chain sync send/recv

## Context

Replication requires manual git commands. No freechains
command to orchestrate sync. B can't like begs fetched
from A (no beg registration).

## Approach: TDD — one test at a time

Each step: write test -> run (fail) -> implement -> run
(pass) -> next test.

All tests in `tst/cli-sync.lua`. Uses local paths
(no daemon).

## Files

| File                        | Role                            |
|-----------------------------|---------------------------------|
| `src/freechains.lua`        | sync subcommand + dispatch      |
| `src/freechains/sync.lua`   | recv + send implementation      |
| `src/freechains/replay.lua` | new: replay incoming commits    |
| `src/freechains/chain.lua`  | refactor: extract time effects  |
| `tst/cli-sync.lua`          | tests (grows incrementally)     |

## State commits and local/ removal

### Problem

Local state (authors.lua, posts.lua) lives in
untracked `local/` dir. After recv, incoming commits
are not registered. Replaying from genesis is correct
but we need a checkpoint at merge-base for efficiency.

### Design: committed state with commit keys

Move authors.lua/posts.lua to `.freechains/` (tracked).
Use commit hashes as post keys (not blob hashes).
A separate "freechains: state" commit avoids circularity
— the post commit hash exists before the state commit
records it.

### File layout (new)

```
<chain-repo>/
  .freechains/
    genesis.lua        -- committed
    random             -- committed
    likes/             -- committed
    authors.lua        -- committed (in state commits)
    posts.lua          -- committed (in state commits)
    now.lua            -- UNTRACKED (wall-clock, per-node)
```

### Commit types

| Trailer              | Content                        |
|----------------------|--------------------------------|
| `freechains: post`   | post file only                 |
| `freechains: like`   | like file only                 |
| `freechains: state`  | authors.lua + posts.lua update |
| (none)               | git-compat post (treat as post)|
| (merge)              | skip during replay             |
| (genesis)            | skip during replay             |

### When to create state commits

Only before sync — minimal frequency:

- **Before send**: so the receiver gets a valid
  checkpoint at merge-base
- **Before recv**: so merge-base has correct state
  for replay after merge

Multiple posts/likes without sync produce zero state
commits. State is kept on disk (modified but not
committed) until sync.

### On post/like

1. Load authors.lua/posts.lua from disk (working tree)
2. Run time effects + immediate effects
3. Write authors.lua/posts.lua to disk (NOT committed)
4. `git add` only the post/like file (selective)
5. `git commit` with post/like trailer
6. State files stay dirty in working tree — that's OK

### On recv

1. Commit state ("freechains: state") if dirty
2. `git fetch <remote> main`
3. `merge-base HEAD FETCH_HEAD` -> base
4. Load state from base tree
   (`git show base:.freechains/authors.lua`)
5. `git merge --no-edit FETCH_HEAD`
6. Replay commits from `base..HEAD` in `--date-order`
   (skip merges, genesis, state commits)
7. Write authors.lua/posts.lua to disk
8. Commit state ("freechains: state")

### On send

1. Commit state ("freechains: state") if dirty
2. `git push <remote> main`

### On query

Compute time effects in memory, return result.
Do NOT commit. `now.lua` (untracked) tracks last
processed wall-clock time.

### On clone

No state commits exist yet. Initialize authors.lua/
posts.lua from genesis pioneers (same as current
`pioneers()`). Write to disk. First state commit
happens at first sync.

### Replay logic

Walk `base..HEAD` in `--date-order --no-merges`:

    git log --reverse --date-order --no-merges
        --format='%H %at %GK' base..HEAD

For each commit:
    1. Parse trailer (freechains: post/like/state/none)
    2. Skip state commits
    3. Run time_effects(G, commit_time, sign)
    4. Apply immediate effects:
       - post (or no trailer): register in G.posts,
         deduct from G.authors
       - like: parse target, cost + tax + split
    5. Cap all authors at max

### Migration

- chain.lua: `git add` selective (not `.freechains/`)
- chain.lua: remove `local/` from all paths
- chains.lua: pioneers() writes `.freechains/authors.lua`
  (not `local/authors.lua`)
- chains.lua: remove `mkdir -p local/`, remove
  `.git/info/exclude` entry for `local/`
- chains.lua: `now.lua` -> `.freechains/now.lua`,
  exclude via `.git/info/exclude .freechains/now.lua`

## Steps

### 1. Test: recv basic (fetch + merge)

Test: A creates chain + posts, B clones, B recvs.
Assert B has A's post on HEAD.

Fail: `sync` command doesn't exist.

Fix: add `sync recv` to argparse in freechains.lua.
Create sync.lua with minimal recv:
- reset local time effects (local/now.lua)
- `git fetch <remote> main`
- `git merge --no-ff --no-edit FETCH_HEAD`

### 2. Migration + recv replay

#### 2a. Migrate local/ to committed state

Move authors.lua/posts.lua from `.freechains/local/`
to `.freechains/` (tracked). See "Migration" section.

- chain.lua: selective `git add` (post/like files only,
  not `.freechains/authors.lua` or `posts.lua`)
- chain.lua: load/write from `.freechains/` not `local/`
- chains.lua: pioneers() writes `.freechains/authors.lua`
- chains.lua: now.lua -> `.freechains/now.lua` (excluded)
- Remove `local/` dir, update skel

#### 2b. State commit function

New function (common.lua or sync.lua):

    commit_state(REPO)
        git add .freechains/authors.lua .freechains/posts.lua
        git commit --trailer 'freechains: state'
            --allow-empty-message -m ''

Called before send/recv if working tree is dirty.

#### 2c. Extract time effects from chain.lua

chain.lua:27-90 is inline. Extract into a shared
function:

    time_effects(G, NOW_s, sign)
        -- discount scan (lines 33-61)
        -- consolidation scan (lines 65-77)
        -- cap (lines 80-86)

chain.lua calls time_effects(G, NOW.s, ARGS.sign).

#### 2d. Replay in sync.lua

After fetch + merge, replay incoming commits:

    base = git merge-base old_HEAD FETCH_HEAD
    Load G from base tree:
        git show base:.freechains/authors.lua
        git show base:.freechains/posts.lua

    git log --reverse --date-order --no-merges
        --format='%H %at %GK' base..HEAD

For each commit:
    1. Parse trailer
    2. Skip state commits
    3. Run time_effects(G, commit_time, sign)
    4. Apply immediate effects:
       - post (or no trailer): register in G.posts,
         deduct from G.authors
       - like: parse target, cost + tax + split
    5. Cap all authors at max

Write G to disk, commit state.

#### 2e. Test: recv bidirectional

Test: A posts, B recvs. B posts, A recvs.
Assert both have all posts.
Assert .freechains/posts.lua has entries for all posts.

### 3. Test: recv already up to date

Test: B recvs from A when nothing new.
Assert no error (silent no-op).

Fail: merge fails on "already up to date" with --no-ff.

Fix: detect up-to-date (FETCH_HEAD == HEAD or
merge-base check), skip merge.

### 4. Test: recv unrelated histories

Test: A and C create independent chains, C recvs
from A. Assert ERROR.

Fail: merge fails but no proper error.

Fix: check genesis match before merge. If genesis
differs -> `ERROR : chain sync : unrelated histories`.

### 5. Test: recv conflict

Test: A and B both post to log.txt, A recvs from B.
Assert ERROR about conflict.

Fail: merge fails but no proper error.

Fix: dry-run merge (--no-commit --no-ff), if fails ->
abort + `ERROR : chain sync : merge conflict`.

### 6. Test: recv begs + registration

Test: A begs, B clones, B recvs (gets beg refs).
Assert B's local/posts.lua has blocked entry.

Fail: no beg fetch, no registration.

Fix: add to recv:
- `git fetch <remote> refs/begs/*:refs/begs/*`
- scan refs/begs/, register in posts.lua + authors.lua

### 7. Test: recv begs + cross-host like

Test: A begs, B clones, B recvs, B likes A's beg.
Assert beg merged into B's HEAD.

Fail/pass: should pass if step 6 registration works
(is_beg detection finds the blocked entry).

### 8. Test: recv beg pruning

Test: A begs, B clones, B recvs, B likes beg (merged).
Then B recvs again from A.
Assert merged beg ref is pruned.

Fail: no pruning logic.

Fix: after merge, scan refs/begs/ with
`merge-base --is-ancestor`, delete merged refs.

### 9. Test: send basic

Test: A creates chain + posts, B clones, A sends to B.
Assert B has A's post.

Fail: `sync send` not implemented.

Fix: add send to sync.lua:
- `git push <remote> main`

### 10. Test: send begs

Test: A begs, B clones, A sends to B.
Assert B has A's beg ref.

Fail: no beg push.

Fix: add `git push <remote> refs/begs/*:refs/begs/*`
to send.

## Future steps (Phase B -- validation)

After basic sync works:
- B1: signature verification per fetched commit
- B2: hard fork detection (7d / 100 posts)
- B3: conflict resolution by reputation

## Current state

- Step 1 test passes (`make test T=cli-sync`)
- `src/freechains.lua`: sync subcommand added (argparse
  + dispatch to `freechains.sync`)
- `src/freechains/sync.lua`: recv does fetch + merge,
  send does push (minimal)
- `tst/cli-sync.lua`: step 1 + step 2 tests

### Next: Step 2 — migration + recv replay

Implementation order:
1. Migrate local/ to committed state (2a)
2. Add commit_state() function (2b)
3. Extract time_effects() from chain.lua (2c)
4. Add replay logic to sync.lua (2d)
5. Update step 2 test (2e)
6. Run all tests — existing + step 2 should pass

### Pending: begs.md TODO update

Change line 458 in `.claude/plans/begs.md`:
`"Impl: register fetched begs"` -> `"see sync.md step 6"`

## Done

- [x] Step 1: recv basic
- [x] Rename "stage/unstage" -> "local time effects"
  across code + 8 plan files

## TODO

- [ ] Step 2: recv bidirectional
- [ ] Step 3: recv already up to date
- [ ] Step 4: recv unrelated histories
- [ ] Step 5: recv conflict
- [ ] Step 6: recv begs + registration
- [ ] Step 7: recv begs + cross-host like
- [ ] Step 8: recv beg pruning
- [ ] Step 9: send basic
- [ ] Step 10: send begs
