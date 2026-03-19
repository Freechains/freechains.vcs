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
    genesis.lua        -- tracked
    random             -- tracked
    likes/             -- tracked
    authors.lua        -- tracked (committed in state commits)
    posts.lua          -- tracked (committed in state commits)
    now.lua            -- UNTRACKED (.git/info/exclude)
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

- **Before send**: so the receiver can load our state
  from our tree (winner side needs committed state)
- **After recv**: to persist replayed state
- **NOT before recv**: we have state on disk already

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

### On send

1. Commit state ("freechains: state") if dirty
2. `git push <remote> main`

### On recv — consensus + validation + merge

1. `git fetch <remote> main`
2. `merge-base HEAD FETCH_HEAD` -> base
3. **Consensus**: compare first commit after base on
   each side. The side with the earlier date wins.
   Winner's state (authors.lua/posts.lua) is truth.
4. **Load winner state**: if winner is local, use
   on-disk state. If winner is remote, load from
   remote HEAD tree (`git show FETCH_HEAD:...`).
5. **Validate loser branch**: replay loser's commits
   one by one (oldest first) against winner's state:
   - Validate: author has enough reps, file-op costs
   - Dry-merge: would this commit merge cleanly with
     winner's tree?
   - On first fail: discard it + all remaining loser
     commits. Pointer = last valid loser commit.
6. **Merge**: combine winner HEAD + validated loser
   pointer. Use git plumbing (`commit-tree` with two
   parents). No `git merge` call.
7. Write state to disk.
8. Commit state ("freechains: state").

### On query

Compute time effects in memory, return result.
Do NOT commit. `now.lua` (untracked) tracks last
processed wall-clock time.

### On clone

No state commits exist yet. Initialize authors.lua/
posts.lua from genesis pioneers (same as current
`pioneers()`). Write to disk. First state commit
happens at first send.

### Consensus rule

The side whose first divergent commit (immediately
after common ancestor) has the **earlier author date**
wins. Winner's branch is accepted as-is. Loser's
branch is validated commit-by-commit.

Both peers arrive at the same decision because the
dates are embedded in the commits.

### Loser validation

For each loser commit (oldest first):
    1. Parse trailer (post/like/state/none)
    2. Skip state commits and merges
    3. Run time_effects(G, commit_time, sign)
    4. Validate immediate effects:
       - post: author has >= 1 rep? file-op cost?
       - like: liker has enough reps?
    5. Dry-merge: would commit apply cleanly to
       winner's tree?
    6. On pass: apply effects to G, advance pointer
    7. On fail: stop. Discard this + all remaining.

### Merge construction

After validation, build merge commit via plumbing:

    # combine winner tree + validated loser changes
    tree = <merged tree of winner + valid loser>
    git commit-tree $tree \
        -p <winner HEAD> \
        -p <loser validated pointer> \
        -m ''
    git update-ref refs/heads/main <new merge commit>

### Migration (DONE)

- chain.lua: `git add` only the post/like file (already
  selective at line 281)
- chain.lua: `L` path changed to `.freechains/`
- chains.lua: pioneers() writes `.freechains/authors.lua`
- chains.lua: removed `mkdir -p local/`
- chains.lua: only `now.lua` in `.git/info/exclude`
  (authors.lua and posts.lua are tracked)

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

#### 2b. State commit (inline in sync.lua)

Before send (and after recv), commit state if dirty:

    git add .freechains/authors.lua .freechains/posts.lua
    git diff --cached --quiet  (exit 1 = dirty)
    if dirty:
        git commit --allow-empty-message
            --trailer 'freechains: state' -m ''

#### 2c. Extract time effects from chain.lua

chain.lua:27-90 is inline. Extract into a shared
function:

    time_effects(G, NOW_s, sign)
        -- discount scan (lines 33-61)
        -- consolidation scan (lines 65-77)
        -- cap (lines 80-86)

chain.lua calls time_effects(G, NOW.s, ARGS.sign).

#### 2d. Recv: consensus + validation + merge

1. Fetch
2. Find merge-base
3. Consensus: earlier first-commit wins
4. Load winner state
5. Validate loser commits (replay + dry-merge)
6. Build merge commit (plumbing)
7. Write state to disk
8. Commit state

See "On recv" section above for full details.

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
Assert: loser's conflicting commit (and subsequent)
are discarded. Winner's content preserved.

Fail: no validation/discard logic.

Fix: during loser validation, dry-merge each commit.
On conflict, discard from that point. Merge only
the valid prefix.

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

## Future steps

- Hard fork detection (7d / 100 posts)
- Signature verification per fetched commit

## Current state

- Step 1 test passes (`make test T=cli-sync`)
- `src/freechains.lua`: sync subcommand added (argparse
  + dispatch to `freechains.sync`)
- `src/freechains/sync.lua`: recv does fetch + merge,
  send does push (minimal)
- `tst/cli-sync.lua`: step 1 + step 2 tests

### Next: Step 2 — consensus + validation + merge

Implementation order:
1. ~~Migrate local/ to committed state (2a)~~ DONE
2. State commit inline in sync.lua (2b)
3. Extract time_effects() from chain.lua (2c)
4. Recv: consensus + validation + merge (2d)
5. Update step 2 test (2e)
6. Run all tests

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
