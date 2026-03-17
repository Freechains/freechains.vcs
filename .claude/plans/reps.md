# Reputation: Likes, Dislikes, and Pioneers

## Overview

Reputation is a per-author and per-post integer tracked
per chain.
Internally stored with 1000x precision (external 1 =
internal 1000).
External values are truncated toward zero:
`ext = sign(int) * (abs(int) // 1000)`.

## Internal vs External

| External | Internal |
|----------|----------|
| 1        | 1000     |
| 30       | 30000    |
| 0        | 0..999   |
| -1       | -1000    |

All operations use internal values.
Queries return external (truncated toward zero).

## Initial Reputation: Pioneers

Each chain starts with a total of **30 reputation** split
equally among its pioneers:

| Pioneers | Reps each (ext) | Internal  |
|----------|-----------------|-----------|
| 1        | 30              | 30000     |
| 2        | 15              | 15000     |
| 3        | 10              | 10000     |
| N        | 30 / N          | 30000 / N |

Pioneers are defined by their entries in
`reps/authors.lua`, which is created in the genesis
commit alongside `genesis.lua`.
There is no separate `pioneers` field in genesis —
the initial non-zero entries *are* the pioneers.
Non-pioneer authors start with **0 reputation**.

Chains without pioneers have an empty
`reps/authors.lua` — no reputation gate at all.

### Special chain types

| Type        | Reputation rule                     |
|-------------|-------------------------------------|
| `#` public  | Pioneer-based (30 / N)              |
| `$` private | All holders of shared key = infinite|
| `@` personal| Key holder = infinite               |

## Constraints

| Rule | Name | Effect                        | Ref             |
|------|------|-------------------------------|-----------------|
| 4.a  | min  | Author needs >= 1 rep to post | Sybil gate      |
| 4.b  | max  | Author capped at 30 reps      | Spend incentive |
| 4.c  | size | Post <= 128 KB                | DDoS prevention |
| 5    | ops  | Each file op costs 1 rep      | Edit throttle   |

No post expiry — posts are permanent.

## Actions and Costs

### Posting (Rule 2 — Expense)

A signed post costs **-N rep** (N * 1000 internal)
where N = number of file operations (Rule 5),
**temporarily**.
The cost is refunded after a **variable discount
period** (0–12 hours) that depends on subsequent
activity from reputed authors.

```
post block:
    N = count file ops outside .freechains/
    if author.reps < N * 1000:
        state = BLOCKED
    else:
        state = ACCEPTED
    author.reps -= N * 1000
    add to time/posts.lua with state "00-12"
        and cost = N * 1000
```

If the author's reputation is insufficient (Rule 4.a),
the post is accepted into the DAG but marked
**BLOCKED** (invisible to consensus).

### File Operation Costs (Rule 5 — Per-Op Expense)

Each file operation outside `.freechains/` costs
**1 rep** (1000 internal).
Operations: add, modify, delete.
`.freechains/` changes are free (deterministic,
verifiable by recomputation).

A normal post adds 1 file → 1 rep.
An edition touching 3 files → 3 rep.
A mass delete of 100 files → 100 rep (self-limiting).

```
post:
    N = count file ops outside .freechains/
        (via git diff-tree --no-commit-id -r )
    author.reps -= N * 1000
    add entry to time/posts.lua ("00-12")
        with cost = N * 1000
```

Discount refunds the full N * 1000.
Consolidation still grants +1/day (1000 internal).
Heavy edits drain rep over time — natural pressure.

#### Validation at Fetch/Merge

For each incoming commit:
1. `git diff-tree --no-commit-id -r <commit>`
2. Count A/M/D entries outside `.freechains/`
3. Verify author had >= N * 1000 reps at that
   DAG position
4. Reject commit if insufficient

#### Editions and Community Moderation

Editions (modify/delete) are allowed.
Community recourse: dislike bad edits.
If dislikes accumulate, the post (commit) gets
REVOKED — its file changes are stripped.
Authors can self-correct by reverting in a new
commit (costs more rep).

### Variable Discount Period (Rule 2)

The discount period varies from 0 to 12 hours based on
subsequent reputed activity:

```
subsequent_reps = sum of reps of authors who posted
                  after this post
total_reps      = total reputation in the chain
ratio           = subsequent_reps / total_reps
discount_secs   = 43200 * max(0, 1 - 2*ratio)
```

| Ratio | Discount | Meaning                    |
|-------|----------|----------------------------|
| 0.0   | 12h      | No activity after post     |
| 0.25  | 6h       | 25% of reps active         |
| 0.5+  | 0h       | 50%+ of reps active        |

The discount is **not stored** — it is recomputed on
every commit because new activity shortens it.

When discount ends:
- Refund: `author.reps += 1000`
- Transition: entry moves from state `"00-12"` to
  `"12-24"` in `time/posts.lua`

### Consolidation (Rule 1.b — Emission)

After the discount period ends AND 24h have passed
since the post's timestamp:

```
last = time_authors[author]
if NOW - last >= 86400:
    author.reps += 1000
    time_authors[author] = last + 86400
    remove from time/posts.lua
else:
    keep in time/posts.lua (retry next commit)
```

Grant slots advance by fixed 24h from last grant,
not from NOW.
This prevents "wasting" time if commits are
infrequent — multiple entries can consolidate in
one commit if enough 24h slots have elapsed.

The author enters `time/authors.lua` at first signed
post (`time_authors[author] = NOW`), so `last` is
never nil during consolidation.

Cap at 30000 is applied after all effects (step 4).

Only **1 consolidated post per author per 24h slot**.
This is the only way to create new reps in the system.

### Like / Dislike (Rules 3.a, 3.b — Transfer)

Likes and dislikes are separate subcommands.
The number is always a positive integer.
Internally both produce a like commit — dislike
negates the number.

```
freechains chain <alias> like 1 post <hash> --sign <key>
freechains chain <alias> dislike 1 post <hash> --sign <key>
```

#### Like targeting a post

```
Like(+N, post):
    liker.reps -= 1000          (cost)
    tax = N * 1000 * 10 / 100   (10% burned)
    delivered = N * 1000 - tax
    post_author.reps += delivered / 2
    post.reps        += delivered / 2
```

#### Like targeting an author

```
Like(+N, author):
    liker.reps    -= 1000        (cost)
    tax = N * 1000 * 10 / 100    (10% burned)
    delivered = N * 1000 - tax
    target_author.reps += delivered
```

#### Dislike (negative N)

Same formulas apply with negative values.
Dislikes are immediate — no maturation delay.

#### 10% Tax

Every like operation burns 10% of the transferred
amount.
This prevents reputation cycling exploits
(A likes B likes C likes A).

### Self-Interactions

- **Self-like**: allowed (half goes to post, half
  to author — net effect is reduced by cost + tax)
- **Self-dislike**: allowed

### Content Revocation (Rule 3.b)

A post becomes **REVOKED** when:
- It has **>= 3 dislikes**, AND
- The number of **dislikes > likes**

When REVOKED, the post's payload is stripped (not
retransmitted).
The post hash remains in the DAG (metadata only).
If the post later receives enough likes to reverse the
condition, it returns to ACCEPTED.

## Block States

A post has three possible states:

| State    | Meaning                                       |
|----------|-----------------------------------------------|
| ACCEPTED | Author has reps; linked in DAG                |
| BLOCKED  | Author's reps too low; not linked             |
| REVOKED  | dislikes >= 3 AND dislikes > likes; no payload|

### State Machine

```
start -> reps >= 1 -> ACCEPTED <-> +/- reps -> ACCEPTED
      -> reps  = 0 -> BLOCKED  -> +1 like   -> ACCEPTED
                                             -> REVOKED
ACCEPTED -> dislikes >= 3 AND dislikes > likes -> REVOKED
REVOKED  -> likes >= dislikes                  -> ACCEPTED
```

A BLOCKED post can become ACCEPTED if the author
later receives enough likes.
A REVOKED post keeps its metadata but loses its
payload.

## Storage

Reputation state lives inside each chain repo under
`.freechains/`:

```
<chain-repo>/
  .freechains/
    genesis.lua
    likes/
    reps/
      authors.lua          -- author -> internal reputation
      posts.lua            -- post -> internal reputation
    time/
      posts.lua            -- posts in discount or consolidation
      authors.lua          -- last grant-slot timestamp per author
    local/                 -- untracked local state
      now.lua              -- last staged timestamp
```

The `chains add` command calls `skel()` to create all
directories and default files before copying genesis input.
All files in `reps/` and `time/` default to `return {}`.
Genesis input's `reps/authors.lua` overwrites the default
(pioneers get initial reps).

All files are tracked by git (committed), except
`local/` which is excluded via `.git/info/exclude`.

`stage()` (local-staging.md) writes to tracked `reps/`
and `time/` files on every command (including queries)
to reflect time effects up to NOW.
These writes are uncommitted — the next post/like
commit picks them up naturally.
Before merge, tracked files must be restored to their
committed state (see local-staging.md, merge.md).

### reps/authors.lua

Maps each author's public key to their internal
reputation:

```lua
return {
    ["CA6391CE..."] = 29000,
    ["78397501..."] = 1350,
}
```

### reps/posts.lua

Maps posts to their internal reputation sum:

```lua
return {
    ["a1b2c3d4..."] = 1350,
    ["e5f6g7h8..."] = -1350,
}
```

### time/posts.lua

Tracks posts in discount period (`"00-12"`) or
awaiting consolidation (`"12-24"`):

```lua
return {
    ["a1b2c3d4..."] = { author="CA6391CE...", time=1710288000, state="00-12" },
    ["e5f6g7h8..."] = { author="CA6391CE...", time=1710201600, state="12-24" },
}
```

- `"00-12"`: post in variable discount period (Rule 2).
  Discount is recomputed on every commit.
  When discount ends: refund -1, transition to `"12-24"`.
- `"12-24"`: discount ended, awaiting 24h consolidation
  (Rule 1.b).
  When 24h passed AND author's grant slot is open:
  grant +1, remove entry.
  Otherwise keep entry for retry on next commit.

### time/authors.lua

Last grant-slot timestamp per author.
Initialized to NOW on first signed post.
Advanced by +24h on each consolidation grant:

```lua
return {
    ["CA6391CE..."] = 1710374400,
}
```

### Update frequency

All files are updated on **every commit** (post or
like).

## Processing on Every Commit

```
on every commit (post, like, or dislike):
    1. scan time/posts.lua:
       for each "00-12" entry:
           recompute discount:
               subsequent_reps = sum of reps of authors
                   who posted after this post
               total_reps = sum of all reps in authors.lua
               ratio = subsequent_reps / total_reps
               discount = 43200 * max(0, 1 - 2*ratio)
           if NOW >= entry.time + discount:
               authors[entry.author] += 1000
               entry.state = "12-24"
       for each "12-24" entry:
           if NOW >= entry.time + 86400:
               last = time_authors[entry.author]
               if NOW - last >= 86400:
                   authors[entry.author] += 1000
                   time_authors[entry.author] = last + 86400
                   remove entry from time/posts.lua
               else:
                   keep entry (retry next commit)
       remove processed entries from time/posts.lua
    2. apply this commit's immediate effects:
       post:    N = count file ops outside .freechains/
                author.reps -= N * 1000
                add entry to time/posts.lua ("00-12")
                    with cost = N * 1000
                if time_authors[author] is nil:
                    time_authors[author] = NOW
       like:    liker.reps -= 1000
                tax + split to target
       dislike: liker.reps -= 1000
                tax + split (negative) to target
                check revocation threshold
    3. gate: check author has >= 1 rep (Rule 4.a)
       -> ACCEPTED or BLOCKED
    4. cap: clamp all authors at 30000
    5. write all modified files
    6. git add + git commit
```

## Computation

Reputation can be recomputed from scratch by walking
the DAG in `--date-order`:

```
load reps/authors.lua from genesis commit
for each commit after genesis in git log --date-order:
    process time effects (discount, consolidation)
    if commit has freechains-like header:
        parse sign, number, target
        liker.reps -= 1000
        tax = abs(number) * 1000 * 10 / 100
        delivered = number * 1000 - sign(number) * tax
        if target is post:
            post_author.reps += delivered / 2
            post.reps        += delivered / 2
        elif target is author:
            target_author.reps += delivered
    elif commit is a regular post:
        author.reps -= 1000
        add to time tracking
    (skip merge-only commits)
    cap all authors at 30000
```

## Git Representation

Likes are stored as commits with:

- **Empty tree** (no payload — same tree as genesis)
- **Extra header** identifying the target and value
- **Signed** by the liker's key (required for authorship)

```
tree 4b825dc...           (empty tree)
parent <HEAD>
author <pubkey> <timestamp>
committer <pubkey> <timestamp>
freechains-like: +1 <target-hash-or-pubkey>

```

This makes likes first-class blocks in the DAG,
synchronized via the same git fetch/merge mechanism as
regular posts.

## CLI Commands

```
freechains chain <alias> like <N> <target> <id> --sign <key> [--why <reason>]
freechains chain <alias> dislike <N> <target> <id> --sign <key> [--why <reason>]
freechains chain <alias> reps <pubkey-or-hash>
```

`reps` returns the external integer (internal // 1000,
truncated toward zero).

## Test: Time Flow Example

1-pioneer chain, KEY has 30 reps (30000 internal).

```
t=0:    KEY posts P1 (signed)
        authors:     KEY=29000 (-1000)
        time/posts:  P1={author=KEY, time=0, state="00-12"}

t=0:    KEY posts P2 (signed)
        -- scan "00-12": P1 discount recomputed
        --   subsequent_reps: KEY posted after P1, KEY has 29000
        --   total_reps: 29000
        --   ratio = 29000/29000 = 1.0 >= 0.5
        --   discount = 0
        --   NOW(0) >= 0+0 -> refund P1
        authors:     KEY=29000 (29000+1000-1000)
        time/posts:  P1={..., state="12-24"}
                     P2={author=KEY, time=0, state="00-12"}

t=0:    KEY posts P3 (signed)
        -- scan "00-12": P2 discount = 0 (ratio=1.0) -> refund
        -- scan "12-24": P1 time=0, NOW=0 < 0+86400 -> wait
        authors:     KEY=29000 (29000+1000-1000)
        time/posts:  P1={..., state="12-24"}
                     P2={..., state="12-24"}
                     P3={author=KEY, time=0, state="00-12"}

t=24h:  KEY posts P4 (signed)
        -- scan "00-12": P3 discount = 0 -> refund
        -- scan "12-24": P1 time=0, NOW=86400 >= 86400
        --   time_authors[KEY] absent -> grant +1
        --   authors[KEY] += 1000, cap 30000
        --   time_authors[KEY] = 0
        -- scan "12-24": P2 time=0, NOW=86400 >= 86400
        --   time_authors[KEY] = 0, 0-0 = 0 < 86400
        --   -> no grant (1/day limit), discard
        authors:     KEY=30000 (29000+1000+1000-1000, capped)
        time/posts:  P3={..., state="12-24"}
                     P4={author=KEY, time=86400, state="00-12"}
        time/authors: KEY=0

t=48h:  KEY posts P5 (signed)
        -- scan "00-12": P4 discount = 0 -> refund
        -- scan "12-24": P3 time=0, NOW=172800 >= 86400
        --   time_authors[KEY]=0, 0-0=0 < 86400 -> no grant
        --   discard P3
        authors:     KEY=30000 (capped)
        time/posts:  P5={author=KEY, time=172800, state="00-12"}
        time/authors: KEY=0
```

Observations:
- Posts are effectively free in active chains (discount=0)
- Consolidation grants +1/day, capped at 30
- Pioneer stays at 30 despite posting (cost refunded)
- Matches Kotlin test c03/c04 behavior (reps=30 after posts)

## Related Plans

- [chains.md](chains.md) — chain types and pioneer setup
- [commands.md](commands.md) — CLI command mapping
- [consensus.md](consensus.md) — reputation as validation
  gate
- [layout.md](layout.md) — filesystem layout including
  `.freechains/`
- [tests.md](tests.md) — Sections C, M, N test reputation
- [references.md](references.md) — papers, docs, guides

## Done

- [x] Plan: internal/external rep model (1000x)
- [x] Plan: 10% tax on likes
- [x] Plan: like/dislike split subcommands
- [x] Plan: self-like allowed
- [x] Plan: variable discount (0-12h, Rule 2)
- [x] Plan: consolidation regrant (+1/day, Rule 1.b)
- [x] Plan: 3 block states (ACCEPTED/BLOCKED/REVOKED)
- [x] Plan: 30-rep cap (Rule 4.b)
- [x] Plan: revocation threshold (Rule 3.b)
- [x] Plan: time/ storage (posts.lua, authors.lua)
- [x] Tests: cli-like.lua (like command structure)
- [x] Tests: reps.lua (reputation math)
- [x] Impl: like/dislike commands in src/freechains
- [x] Impl: .freechains/likes/ created at chain init
- [x] Impl: skel() creates full .freechains/ skeleton
- [x] Impl: reps/ nested dir (authors.lua, posts.lua)

## TODO

- [x] Impl: time/ dir created by skel()
- [x] Impl: gate check (Rule 4.a, > 0 internal rep to post)
- [x] Impl: variable discount engine (Rule 2)
- [x] Impl: consolidation engine (Rule 1.b)
- [x] Impl: 30-rep cap (Rule 4.b)
- [x] Impl: signing gate (--sign required, --beg bypass)
- [x] Impl: reps command in src/freechains
- [x] Refactor: merge reps/ + time/ into authors.lua + posts.lua
- [x] Refactor: chain.lua flatten (less nesting)
- [x] Tests: variable discount (0-12h)
- [x] Tests: consolidation (+1/day, 24h)
- [x] Tests: 30-rep cap
- [x] Tests: gate check (blocked, accepted, unblocked, beg-with-reps)
- [x] Tests: author-targeted likes (cost, gains, like 2, dislike)
- [ ] Plan: file-op cost model (Rule 5)
- [ ] Impl: file-op count via git diff-tree (Rule 5)
- [ ] Impl: N * 1000 post cost (Rule 5)
- [ ] Impl: fetch/merge file-op validation (Rule 5)
- [ ] Tests: file-op cost (1 file, multi-file, .freechains/ exempt)
- [ ] Impl: revocation state (Rule 3.b)
- [ ] Impl: 128 KB size limit (Rule 4.c)
- [ ] Impl: --beg creates BLOCKED post
- [ ] Tests: revocation threshold
- [ ] Tests: time flow example (above)
