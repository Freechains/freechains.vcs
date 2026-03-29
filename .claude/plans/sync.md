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

| File                              | Role                            |
|-----------------------------------|---------------------------------|
| `src/freechains.lua`              | sync subcommand + dispatch      |
| `src/freechains/chain/sync.lua`   | recv + send implementation      |
| `src/freechains/chain/common.lua` | shared: apply, write, NOW       |
| `tst/cli-sync.lua`               | tests (grows incrementally)     |

## State commits and local/ removal (DONE)

State files moved to `.freechains/state/` (tracked).
Post keys use blob hashes. State commits use
`Freechains: state` trailer. See new-merge.md §1.

### On send

1. Commit state ("freechains: state") if dirty
2. `git push <remote> main`

### On recv — verify + consensus + merge

#### Phase 1: Verify remote (trust)

1. Commit state if dirty (clean working tree)
2. `git fetch <remote> main`
3. `merge-base HEAD FETCH_HEAD` -> com
4. Load state from com tree
   (`git show com:.freechains/authors.lua`)
5. Replay all remote commits (`com..rem`) one by one
6. Compare computed state with remote's last
   `freechains: state` commit
7. If different -> abort (remote is dishonest)

#### Phase 2: Consensus + merge

8. Determine winner/loser (earlier first-commit)
9. **If winner is remote**: use already-computed state
   from step 5 (no re-replay). Replay local (loser)
   commits on top.
10. **If winner is local**: use local state from disk.
    Replay remote (loser) commits on top of local
    state.
11. Merge (git merge or plumbing)
12. Write state to disk.

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

### Remote verification (Phase 1)

Replay remote commits from com..rem against com state.
After replay, compare computed authors/posts with
remote's last "freechains: state" commit tree.
If mismatch -> ERROR (dishonest remote).

This replay also serves as winner state if remote wins
(reused in Phase 2, no re-replay).

### Loser replay (Phase 2)

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

- `src/freechains/chain/sync.lua`: recv with consensus
  + validation + merge. Send is TODO.
- `src/freechains/chain/common.lua`: shared apply, write
- `tst/cli-sync.lua`: steps 1-3 pass

## Done

- [x] Step 1: recv basic
- [x] Step 2: recv bidirectional
- [x] Step 3: recv divergent + consensus
- [x] Rename "stage/unstage" -> "local time effects"
- [x] Migrate local/ to committed state
- [x] Extract time_effects into apply (common.lua)
- [x] Refactor: `freechains/chain/` dir with common.lua
- [x] FF validates remote before accepting (replay
  runs before FF check)

## TODO

- [ ] Step 4: recv unrelated histories
- [ ] Step 5: recv conflict
- [ ] Step 6: recv begs + registration
- [ ] Step 7: recv begs + cross-host like
- [ ] Step 8: recv beg pruning
- [ ] Step 9: send basic
- [ ] Step 10: send begs
- [ ] Like replay in sync.lua (designed in rec-replay.md,
  not yet integrated — `error "TODO"` at line 33)
- [ ] Recursive replay (designed in rec-replay.md,
  sync.lua still uses flat `git log --no-merges`)
