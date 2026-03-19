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

| File                      | Role                              |
|---------------------------|-----------------------------------|
| `src/freechains.lua`      | add sync subcommand + dispatch    |
| `src/freechains/sync.lua` | new: recv + send implementation   |
| `tst/cli-sync.lua`        | tests (grows incrementally)       |

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

### 2. Test: recv bidirectional

Test: A posts, B recvs. B posts, A recvs.
Assert both have all posts.

Fail/pass: should pass with step 1 implementation.

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
- B2: reputation replay at DAG position
- B3: hard fork detection (7d / 100 posts)
- B4: conflict resolution by reputation

## Current state

- Step 1 test passes (`make test T=cli-sync`)
- `src/freechains.lua`: sync subcommand added (argparse
  + dispatch to `freechains.sync`)
- `src/freechains/sync.lua`: recv does fetch + merge,
  send does push (minimal)
- `tst/cli-sync.lua`: step 1 test only

### Next: Step 2 — recv bidirectional

Add test to `tst/cli-sync.lua`:
- A posts, B recvs from A
- B posts, A recvs from B
- Assert both have all posts (diff repos)

Should pass without code changes (step 1 recv
already handles this). If it passes, move to step 3.

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
