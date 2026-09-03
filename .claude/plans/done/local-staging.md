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
A `local/now.lua` (untracked) records the last local
time effects timestamp for monotonic skip.

## Implementation (done)

### skel()

Creates `.freechains/local/` dir, `local/now.lua`
(`return 0`), and appends `.freechains/local/` to
`.git/info/exclude`.

### Local time effects block (`elseif args.chain`)

Inlined at chain command level (no function):

```lua
-- local time effects: advance discount + consolidation
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

Local time effects write to `local/` files (untracked).
Since `local/` is git-excluded, merge is unaffected.

### Reset protocol (before fetch/merge)

Reset `local/now.lua` to `return 0` so local time
effects re-process from the merged state after merge.

Since `local/` files are git-excluded (untracked),
no `git checkout` cleanup is needed.

### Why this is safe

- Local time effects only advance discount +
  consolidation — no new posts or likes
- `local/` files are derived state, re-computable
  from the DAG
- `local/now.lua` reset forces full re-scan from
  the merged state

### Implementation

The `chain sync` command must:

1. Reset: set local/now.lua to 0
2. `git fetch`
3. Validate (consensus pipeline)
4. `git merge --no-ff`
5. Next command triggers local time effects re-scan

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
- [x] Local time effects inlined at chain command level
- [x] Reps query uses local time effects data
- [x] Monotonic guard (skip for cached queries)
- [x] Cap only for query paths
- [x] `write()` scoped inside chain block
- [x] Clone tests create `local/` explicitly
- [x] Plans updated (merge.md, consensus.md, reps.md)
- [x] All tests pass
