# Plan: Implement `time/` Engine (Variable Discount + Consolidation)

## Context

The reputation system currently deducts -1 rep permanently
on every signed post. The paper (SBSeg 2023, Table 2) says
the cost is **temporary** — refunded after a variable
discount period (0-12h) that depends on subsequent reputed
activity. After 24h, posts **consolidate** and grant +1 rep
(1/day/author, capped at 30).

This is tracked via new `.freechains/time/` cache files.
See [reps.md](reps.md) for the full spec.

## Critical Files

| File               | Action | Purpose                              |
|--------------------|--------|--------------------------------------|
| `src/common.lua`   | edit   | Enhance `serial()` for nested tables |
| `src/freechains`   | edit   | `skel()`, `time_process()`, flow     |
| `tst/cli-time.lua` | new    | Time engine tests                    |
| `tst/cli-reps.lua` | edit   | Fix expected values (27->29)         |
| `tst/Makefile`     | edit   | Add cli-time target                  |

## Steps

### Step 1: `serial()` — nested table support

**File**: `src/common.lua` (lines 45-56)

Add `serial_value(v)` helper before `serial()`:
- `type(v) == "table"` -> sorted keys inline:
  `{ author="...", seq=N, state="...", time=N }`
- strings quoted, numbers bare
- otherwise -> `tostring(v)`

Replace line 53 in `serial()`:
`t[k]` -> `serial_value(t[k])`

Backward compatible: flat `{key=number}` unchanged.

### Step 2: `skel()` — create `time/` dir

**File**: `src/freechains` (lines 8-29)

After the `reps/` block, add:
- `mkdir -p <path>/.freechains/time`
- Create `time/authors.lua` + `time/posts.lua`
  both initialized to `return {}\n`

Same pattern as existing reps/ files.

### Step 3: `time_process()` function

**File**: `src/freechains` (insert before line 154)

Signature:
`local function time_process(REPO, NOW, authors)`

**Phase 1 — discount ("00-12" entries)**:

Each time entry stores `seq` (commit count at creation).
To find subsequent authors:

```
current = git rev-list --count HEAD
n_after = current - entry.seq - 1
if n_after > 0:
    keys = git log -<n_after> --format='%GK' HEAD
```

Then compute discount:

```
total_reps = sum of positive values in authors
subsequent_reps = sum of authors[key] for unique keys
ratio = subsequent_reps / total_reps
discount = 43200 * max(0, 1 - 2*ratio)
if NOW >= entry.time + discount:
    authors[entry.author] += 1000
    entry.state = "12-24"
```

**Phase 2 — consolidation ("12-24" entries)**:

Sort by time (oldest first). For each:

```
if NOW >= entry.time + 86400:
    last = time_authors[entry.author]
    if last is nil OR entry.time - last >= 86400:
        authors[entry.author] += 1000
        cap at 30000
        time_authors[entry.author] = entry.time
    remove entry from time_posts
```

**Phase 3 — cap**: clamp all authors at 30000.

Returns: `changed` bool, file list string for git add.

### Step 4: Integrate into post/like flow

**File**: `src/freechains` (lines 358-420)

Revised flow:

```
1. dofile authors.lua              (existing)
2. immediate effects               (existing)
   post: author -= 1000
   like: cost + tax + split
3. write reps files                (existing)
4. git add + git commit            (existing)
5. if signed post:
   a. seq = rev-list --count HEAD
   b. key = NOW.."-"..sign:sub(1,8)
   c. add entry to time/posts.lua:
      { author=sign, time=NOW, state="00-12", seq=seq-1 }
   d. write time/posts.lua
   e. git add .freechains/time/
   f. git commit --amend (same signing flags)
6. time_process(REPO, NOW, authors)
   a. if changed:
      write reps/authors.lua + time/ files
      git add changed files
      git commit --amend
7. hash = rev-parse HEAD
8. print(hash)
```

Why `seq-1`: the count includes the just-committed post,
but seq should reflect "commits before this one" so that
`current - seq - 1` gives commits AFTER this post.

### Step 5: Update `tst/cli-reps.lua`

Test `reps-after-3-posts` expects 27 (3 permanent costs).
With time engine: P2 refunds P1, P3 refunds P2, so
reps = 30-1+1-1+1-1 = 29.

Change: `assert(out == "27"` -> `assert(out == "29"`

Other tests stay the same:
- `reps-after-1-post` (29): no subsequent activity yet,
  discount=12h, not elapsed -> no refund -> 29. OK.
- Like tests: likes don't create time entries. In 2-pioneer
  chain, ratio < 0.5 so no instant refund. Unchanged.

### Step 6: New `tst/cli-time.lua`

```
Test 1: "time-discount-instant"
  1p, P1 at --now=0, P2 at --now=0
  reps = 29 (P1 refunded, P2 pending)

Test 2: "time-discount-12h"
  1p, P1 at --now=0
  reps = 29 (pending)
  P2 at --now=43200 (12h)
  reps = 29 (P1 refunded at 12h, P2 pending)

Test 3: "time-consolidation-24h"
  1p, P1 at --now=0, P2 at --now=86400
  reps = 30 (P1 refunded + consolidated, P2 pending)

Test 4: "time-1-per-day"
  1p, P1+P2+P3 at --now=0, P4 at --now=86400
  reps = 30 (only P1 consolidates, cap)

Test 5: "time-full-flow"
  Full example from reps.md "Test: Time Flow Example"
```

### Step 7: `tst/Makefile`

Add `cli-time` target following existing pattern.

## Existing Functions to Reuse

| Function       | File             | Purpose                       |
|----------------|------------------|-------------------------------|
| `serial()`     | `src/common.lua` | Serialize Lua tables          |
| `exec()`       | `src/common.lua` | Run shell commands            |
| `dofile()`     | Lua built-in     | Load Lua table files          |
| `git_config()` | `src/common.lua` | Configure git repos           |
| `skel()`       | `src/freechains` | Skeleton dir creation         |

## Verification

```
make test T=cli-time   # new time tests
make test T=cli-reps   # existing with updated values
make test T=cli-like   # unaffected
make test T=cli-now    # unaffected (unsigned posts)
```

## Dependency Order

1. `serial()` enhancement (common.lua) — no deps
2. `skel()` update (freechains) — no deps
3. `time_process()` function (freechains) — depends on 1
4. Integration into post/like flow (freechains) — depends on 3
5. Tests (cli-time.lua) — depends on all above
6. Update cli-reps.lua — depends on 4

Steps 1 and 2 can be done in parallel.
Steps 3-4 are sequential.
Steps 5-6 can be done in parallel after 4.

## Risk: Self-Referential Hash

Cannot store the commit hash as key in `time/posts.lua`
because the file is committed — changing it changes the
hash. Solved by using `NOW.."-"..sign:sub(1,8)` as key
and `seq` (commit count) to find subsequent commits via
`git log -N --format='%GK'`.
