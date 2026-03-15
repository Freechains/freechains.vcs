# Plan: Local Staging for Time-aware Queries

## Context

The `reps` query reads stored files which are only
updated on commits (post/like).
To show accurate reps at a given `--now`, time effects
(discount + consolidation) must run first.

Approach: extract the time scan into a `stage()`
function that writes directly to tracked files
(without committing).
A `local/now.lua` (untracked) records the last
staged timestamp for monotonic skip.

## Critical Files

| File              | Action | Purpose                       |
|-------------------|--------|-------------------------------|
| `src/freechains`  | edit   | skel, stage(), reps command   |
| `tst/cli-time.lua`| done  | Failing test already exists   |

## Step 1: Add `local/` to skel + exclude

In `skel()`, create `.freechains/local/` dir.
Write initial `local/now.lua` with `return 0`.

Exclude from git via `.git/info/exclude`
(append after `git init` in `chains add`):

```
.freechains/local/
```

Update the tree comment:

```
-- .freechains/
--   ...
--   local/              -- untracked local state
--     now.lua           -- last staged timestamp
```

## Step 2: Extract time scan into `stage()`

```lua
local function stage (REPO, NOW, sign)
```

Parameters:
- `REPO`: chain repo path
- `NOW`: current timestamp
- `sign`: signer key (nil for queries)

Logic:
1. Load `local/now.lua` — if `sign == nil` and
   `NOW <= stored`, skip (already staged)
2. Load tracked files: `reps/authors.lua`,
   `time/posts.lua`, `time/authors.lua`
3. Run discount scan (using `sign` for
   subsequent-authors if not nil)
4. Run consolidation scan + survivor filter
5. Cap all authors at max
6. Write results to **tracked** files:
   - `reps/authors.lua`
   - `time/posts.lua`
   - `time/authors.lua`
7. Write `local/now.lua = NOW`
8. Return `fc_reps_authors, fc_time_posts,
   fc_time_authors`

No git-add, no commit — just disk writes.
The dirty working tree is intentional; the next
commit picks up these files naturally.

## Step 3: Use stage() in post/like path

```lua
local fc_reps_authors, fc_time_posts,
      fc_time_authors = stage(REPO, NOW, args.sign)
```

Then apply post/like effects on the returned tables.
Write tracked files again after effects.
Git-add + commit as before.

## Step 4: Use stage() in reps command

Before reading reps, call:

```lua
stage(REPO, NOW, nil)
```

Then read `reps/authors.lua` as usual (already
updated on disk by stage).

## Step 5: Monotonic guard

```lua
local stored = dofile(L .. "now.lua")
if sign == nil and NOW <= stored then
    return  -- already staged
end
```

- Queries (sign==nil): skip if already staged
- Posts/likes (sign~=nil): always re-run because
  new entry changes discount computation

## Trace: test time-reps-query-simulates

```
--now=0, 1 pioneer, KEY=30000

P1 at --now=0:
    stage(REPO, 0, KEY):
        sign ~= nil → always run
        discount: empty → skip
        consolidation: empty → skip
        writes tracked files (no change)
        now.lua=0
    post effect: KEY=29000, tposts[1]={"00-12"}
    time_authors[KEY]=0
    writes tracked files, git commit

reps --now=0:
    stage(REPO, 0, nil):
        now.lua=0, NOW(0)<=0 → skip
    read reps/authors.lua → KEY=29000 → ext=29 ✓

reps --now=86400:
    stage(REPO, 86400, nil):
        now.lua=0, NOW(86400)>0 → run
        discount: P1 ratio=0, discount=12h
            86400 >= 0+43200 → refund, KEY=30000
            state="12-24"
        consolidation: P1
            86400 >= 0+86400 → grant
            KEY=31000, last=0+86400=86400, remove
        cap: KEY=30000
        writes tracked files, now.lua=86400
    read reps/authors.lua → KEY=30000 → ext=30 ✓
```

## Merge Concern: Dirty Working Tree

`stage()` writes to tracked files without committing.
Git merge requires a clean working tree.

### Unstage protocol (before fetch/merge)

```bash
git checkout -- .freechains/reps/ .freechains/time/
```

Reset `local/now.lua` to `return 0` so `stage()`
re-processes from the merged state after merge.

### Why this is safe

- `stage()` only advances time effects — it doesn't
  create new posts or likes
- Restoring tracked files loses no real data — the
  effects will be re-computed on the next `stage()`
  call after merge
- `local/now.lua` reset forces full re-scan from
  the merged state

### Implementation

The future `chain sync` / `chain merge` command must:

1. Unstage: restore tracked files + reset now.lua
2. `git fetch`
3. Validate (consensus pipeline)
4. `git merge --no-ff`
5. Next command triggers `stage()` which re-scans

See also: merge.md (clean working tree requirement),
consensus.md (fetch validation pipeline).

## Verification

```
make test T=cli-time
make test T=cli-reps
make test T=cli-like
make test T=cli-now
```
