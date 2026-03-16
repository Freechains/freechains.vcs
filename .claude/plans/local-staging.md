# Plan: Local Staging for Time-aware Queries

## Context

The `reps` query reads stored files which are only
updated on commits (post/like).
To show accurate reps at a given `--now`, time effects
(discount + consolidation) must run first.

Approach: inline the time scan at the `chain` command
level so it runs on **every chain command** (reps,
post, like).
Writes directly to tracked files (without committing).
A `local/now.lua` (untracked) records the last staged
timestamp for monotonic skip.

## Implementation (done)

### skel()

Creates `.freechains/local/` dir, `local/now.lua`
(`return 0`), and appends `.freechains/local/` to
`.git/info/exclude`.

### Stage block (`elseif args.chain`)

Inlined at chain command level (no function):

```lua
-- stage: advance time effects
local fc_reps_authors, fc_time_posts, fc_time_authors
do
    ...load files...
    if args.sign ~= nil or NOW > stored then
        ...discount scan (uses args.sign)...
        ...consolidation scan...
        ...survivor filter...
        ...cap (query paths only)...
        ...write tracked files + now.lua...
    end
end
```

- `args.sign` is nil for reps queries, set for
  post/like — no explicit parameter needed
- Cap runs only for queries (`args.sign == nil`)
  so consolidation +1 isn't capped before post cost
- `write()` is scoped inside the chain block
- All chain subcommands share `fc_reps_authors`,
  `fc_time_posts`, `fc_time_authors`

### Monotonic guard

```
if args.sign ~= nil or NOW > stored then
```

- Queries (sign==nil): skip if NOW <= stored
- Posts/likes (sign~=nil): always re-run because
  new entry changes discount computation

### Clone/sync

`skel()` creates `local/` for new chains.
Clone tests create `local/` + `now.lua` + exclude
explicitly (future sync command will do the same).

## Merge Concern: Dirty Working Tree

Stage writes to tracked files without committing.
Git merge requires a clean working tree.

### Unstage protocol (before fetch/merge)

```bash
git checkout -- .freechains/reps/ .freechains/time/
```

Reset `local/now.lua` to `return 0` so stage
re-processes from the merged state after merge.

### Why this is safe

- Stage only advances time effects — it doesn't
  create new posts or likes
- Restoring tracked files loses no real data — the
  effects will be re-computed on the next stage
  call after merge
- `local/now.lua` reset forces full re-scan from
  the merged state

### Implementation

The future `chain sync` / `chain merge` command must:

1. Unstage: restore tracked files + reset now.lua
2. `git fetch`
3. Validate (consensus pipeline)
4. `git merge --no-ff`
5. Next command triggers stage which re-scans

See also: merge.md (clean working tree requirement),
consensus.md (fetch validation pipeline).

## Verification

```
make test T=cli-time
make test T=cli-reps
make test T=cli-like
make test T=cli-now
make test T=repl-local
make test T=repl-remote
```

## Done

- [x] `local/` dir in skel + `.git/info/exclude`
- [x] Stage logic inlined at chain command level
- [x] Reps query uses staged `fc_reps_authors`
- [x] Monotonic guard (skip for cached queries)
- [x] Cap only for query paths
- [x] `write()` scoped inside chain block
- [x] Clone tests create `local/` explicitly
- [x] Plans updated (merge.md, consensus.md, reps.md)
- [x] All tests pass
