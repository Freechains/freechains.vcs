# Reputation: Likes, Dislikes, and Pioneers

## Overview

Reputation is a per-author and per-post integer tracked
per chain.

## One Currency

There is a single unit. The CLI speaks it raw: `reps`
prints `15450`, `like 450` transfers 450. No external/
internal seam, no truncation, no rounding — exact
integers end to end.

The x1000 scale survives only inside the constants
(`cost = 1000`, `max = 30000`): it exists so the 10% tax
and the 50/50 post split stay integral.

| Constant | Value | Meaning              |
|----------|-------|----------------------|
| `cost`   | 1000  | one signed post/file |
| `max`    | 30000 | cap per author       |

Parameter review and the pending gate work:
[260809-reps.md](260809-reps.md).

## Initial Reputation: Pioneers

Each chain starts with a total of **30000 reputation**
(= `max`) split equally among its pioneers:

| Pioneers | Reps each |
|----------|-----------|
| 1        | 30000     |
| 2        | 15000     |
| 3        | 10000     |
| N        | 30000 / N |

Large N starves pioneers below `cost` — open decision in
[260809-reps.md](260809-reps.md).

Pioneers are defined by the `pioneers` list in
`genesis.lua`. At chain creation/clone, `pioneers()`
returns the initial `G.authors` with reps split equally
among pioneers.
Non-pioneer authors start with **0 reputation**.

Chains without pioneers (no `pioneers` field in
genesis) start with an empty `G.authors` — no
reputation gate at all.

### Special chain types

| Type        | Reputation rule                     |
|-------------|-------------------------------------|
| `#` public  | Pioneer-based (30000 / N)           |
| `$` private | All holders of shared key = infinite|
| `@` personal| Key holder = infinite               |

## Constraints

| Rule | Name | Effect                          | Ref             |
|------|------|---------------------------------|-----------------|
| 4.a  | min  | Author affords the act's cost   | Sybil gate      |
| 4.b  | max  | Author capped at `max` (30000)  | Spend incentive |
| 4.c  | size | Post <= 128 KB                  | DDoS prevention |
| 5    | ops  | Each file op costs `cost`       | Edit throttle   |

Rule 4.a is affordability, not presence: a voter needs
the full vote magnitude (shipped,
[done/260722-bug-reps-debt.md](done/260722-bug-reps-debt.md)),
an author needs `cost` (NOT SHIPPED — the code still gates
on `reps > 0`, see [260809-reps.md](260809-reps.md)).

No post expiry — posts are permanent.

## Actions and Costs

### Posting (Rule 2 — Expense)

A signed post costs **-N * `cost`** where N = number of
file operations (Rule 5), **temporarily**.
The cost is refunded after a **variable discount
period** (0–12 hours) that depends on subsequent
activity from reputed authors.

```
post block:
    N = count file ops (payload actions)
    if author.reps < N * cost:
        state = BLOCKED
    else:
        state = ACCEPTED
    author.reps -= N * cost
    add to posts with maturity "00-12"
```

If the author's reputation is insufficient (Rule 4.a),
the post is accepted into the DAG but marked
**BLOCKED** (invisible to consensus).

### File Operation Costs (Rule 5 — Per-Op Expense)

Each file operation costs **`cost`** (1000).
Operations: add, modify, delete.

A normal post adds 1 file → 1000.
An edition touching 3 files → 3000.
A mass delete of 100 files → 100000 (self-limiting).

```
post:
    N = count file ops
    author.reps -= N * cost
    add entry to posts ("00-12")
```

Discount refunds the full N * `cost`.
Consolidation still grants +`cost`/day.
Heavy edits drain rep over time — natural pressure.

#### Validation at Fetch/Merge

For each incoming commit:
1. `git diff-tree --no-commit-id -r <commit>`
2. Count A/M/D entries (payload actions)
3. Verify author had >= N * `cost` reps at that
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
- Refund: `author.reps += cost`
- Transition: entry moves from maturity `"00-12"` to
  `"12-24"`

### Consolidation (Rule 1.b — Emission)

After the discount period ends AND 24h have passed
since the post's timestamp:

```
last = authors[author].time
if NOW - last >= 86400:
    author.reps += cost
    authors[author].time = last + 86400
    remove the post entry
else:
    keep the entry (retry next commit)
```

Grant slots advance by fixed 24h from last grant,
not from NOW.
This prevents "wasting" time if commits are
infrequent — multiple entries can consolidate in
one commit if enough 24h slots have elapsed.

The author enters `authors` at first signed post
(`authors[author].time = NOW`), so `last` is never nil
during consolidation.

Cap at `max` is applied after all effects (step 4).

Only **1 consolidated post per author per 24h slot**.
This is the only way to create new reps in the system.

### Like / Dislike (Rules 3.a, 3.b — Transfer)

Likes and dislikes are separate subcommands.
The number is always a positive integer.
Internally both produce a like commit — dislike
negates the number.

```
freechains chain <alias> like 1000 post <id> --sign <key>
freechains chain <alias> dislike 1000 post <id> --sign <key>
```

N is raw reps (one post's worth = `cost` = 1000).

Gate: the liker must **afford the full magnitude** —
`reps >= N` — else "insufficient reputation". This
prevents debt (spending more than you hold). The liker pays
the full N, so the transfer conserves reps.

#### Like targeting a post

```
Like(+N, post):
    liker.reps -= N          (cost = full magnitude)
    tax = N * 10 / 100       (10% burned)
    delivered = N - tax
    post_author.reps += delivered / 2
    post.reps        += delivered / 2
```

#### Like targeting an author

```
Like(+N, author):
    liker.reps    -= N       (cost = full magnitude)
    tax = N * 10 / 100       (10% burned)
    delivered = N - tax
    target_author.reps += delivered
```

So a post-like of 1000 delivers 450 to the author, an
author-like of 1000 delivers 900 — neither pays for the
next post on its own. The cheapest grant that posts
immediately is 2223 (post) or 1112 (author); see
[260809-reps.md](260809-reps.md).

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

Revocation is an **explicit** vote, separate from dislikes,
on its own bipolar axis:

```
freechains chain <alias> revoke   1 <hash> --sign <key>
freechains chain <alias> unrevoke 1 <hash> --sign <key>
```

(post-only, so no `post`/`author` target argument — unlike
`like`/`dislike`.)

Stored as a first-class action kind: `action='revoke'` in the
action file (parallel to `action='like'`). The field marks the
revoke axis; `n` sign gives the direction (revoke `n<0`,
unrevoke `n>0`).

The two axes are coupled **asymmetrically**:

| op         | caster | post/author reps | `revoke` sum |
|------------|--------|------------------|--------------|
| `like`     | -n     | +n               | +n           |
| `dislike`  | -n     | -n               | --           |
| `revoke`   | -n     | -n               | -n           |
| `unrevoke` | -n     | -- (burn)        | +n           |

- `revoke` also counts as a **dislike** (removes reps + costs
  the caster); a `dislike` never revokes.
- A positive `like` also counts as an **unrevoke** (liking
  means the post should stay visible); an `unrevoke` never
  credits reps — it only restores visibility, and still costs
  the caster.
- So `like` = `unrevoke` + reps credit, and `revoke` =
  `dislike` + revoke debit.
- The author's free self-revoke skips all reps math, so it is
  **not** a dislike.

Each post keeps two signed sums of the vote magnitude `T.n`
(revoke `n<0`, unrevoke `n>0`), in separate channels:

- **Community** (caster != author): `revoke.others += T.n`.
  Revoked when the net is negative (`others < 0`) — reps-
  weighted (magnitude matters, not a head count).
- **Author** (caster == post author): `revoke.author += T.n`.
  A negative `author` sum is the **absolute** right to be
  forgotten (forces revoked regardless of the community net);
  only the author's own `unrevoke` lifts it.
  - The `author` channel is exclusive to the author's own
    `revoke`/`unrevoke`; a self-`like` feeds `others`.
  - Author `revoke` is **free and ungated** (no reps cost, no
    transfer, works at 0 reps).
  - Author `unrevoke` **costs** the caster, as do all
    community votes.

```
p.revoke = { author = <signed sum>, others = <signed sum> }
is_revoked(p) = (p.revoke.author < 0) OR (p.revoke.others < 0)
```

Both channels are commutative sums, hence order-independent on
sync replay: likes cast *before* a revoke count just the same.
A well-liked post is therefore unrevokable by the community —
only the author's absolute channel still hides it.

The two sums are readable with:

```
$ freechains chain <alias> reps revoke <hash>
-3 2        -- author others ; revoked if either < 0

$ freechains chain <alias> reps revokes
<hash> -3 2 -- both channels of all posts,
<hash>  0 1 -- most revoked first
```

Phase 1 hides the payload on read (metadata + blob stay);
physical stripping / no-retransmit is Phase 2
(`260721-remove-blob.md`).

## Block States

A post has three possible states:

| State    | Meaning                                       |
|----------|-----------------------------------------------|
| ACCEPTED | Author has reps; linked in DAG                |
| BLOCKED  | Author's reps too low; not linked             |
| REVOKED  | author sum < 0 OR community sum < 0; hidden   |

### State Machine

```
start -> reps >= 1 -> ACCEPTED <-> +/- reps -> ACCEPTED
      -> reps  = 0 -> BLOCKED  -> +1 like   -> ACCEPTED
                                             -> REVOKED
ACCEPTED -> author sum < 0 OR others sum < 0 -> REVOKED
REVOKED  -> author sum >= 0 AND others sum >= 0 -> ACCEPTED
```

A BLOCKED post can become ACCEPTED if the author
later receives enough likes.
A REVOKED post keeps its metadata but loses its
payload.

## Storage

Reputation state is **never committed**. It is derived
from the action DAG and cached per-commit as local
snapshots (see `280808-redesign.md`):

```
<chain-repo>/
  actions/ab/<aid>.lua  -- tracked (the actions themselves)
  genesis.lua           -- tracked
  random                -- tracked
  .git/states/<cid>.lua -- LOCAL snapshot of the whole G
```

The `chains add` command writes the tracked trio and
snapshots genesis; `pioneers()` returns the initial
authors table (splitting 30000 equally) straight into
that snapshot — no tree file.

`G = { authors, posts, order, now }`. Every accepted
action writes a fresh snapshot keyed by its commit;
readers load `STATE(rev)` rather than any worktree file.

### G.authors

Maps each author's public key to their reputation
and grant-slot timestamp:

```lua
{
    ["CA6391CE..."] = { reps=29000, time=1710374400 },
    ["78397501..."] = { reps=1350 },
}
```

- `reps`: reputation (raw units)
- `time`: last grant-slot timestamp (initialized on
  first signed post, advanced +24h on consolidation)

### G.posts

Tracks posts in discount period (`"00-12"`) or
awaiting consolidation (`"12-24"`):

```lua
{
    ["a1b2c3d4..."] = { author="CA6391CE...", time=1710288000, maturity="00-12", reps=0 },
    ["e5f6g7h8..."] = { author="CA6391CE...", time=1710201600, maturity="12-24", reps=450 },
}
```

- `"00-12"`: post in variable discount period (Rule 2).
  Discount is recomputed on every commit.
  When discount ends: refund `cost`, transition to
  `"12-24"`.
- `"12-24"`: discount ended, awaiting 24h consolidation
  (Rule 1.b).
  When 24h passed AND author's grant slot is open:
  grant `cost`, remove entry.
  Otherwise keep entry for retry on next commit.
- `reps`: accumulated likes/dislikes on this post
- `"beg"`: unfunded post, awaiting a sponsor's like
  (see `begs.md`)

### Update frequency

`G` is recomputed on **every action** (post or vote)
and snapshotted at the resulting commit.

## Processing on Every Action

```
on every action (post, like, or dislike):
    1. scan G.posts:
       for each "00-12" entry:
           recompute discount:
               subsequent_reps = sum of reps of authors
                   who posted after this post
               total_reps = sum of all reps in G.authors
               ratio = subsequent_reps / total_reps
               discount = 43200 * max(0, 1 - 2*ratio)
           if NOW >= entry.time + discount:
               authors[entry.author].reps += cost
               entry.maturity = "12-24"
       for each "12-24" entry:
           if NOW >= entry.time + 86400:
               last = authors[entry.author].time
               if NOW - last >= 86400:
                   authors[entry.author].reps += cost
                   authors[entry.author].time = last + 86400
                   remove entry from G.posts
               else:
                   keep entry (retry next action)
    2. apply this action's immediate effects:
       post:    N = count file ops
                author.reps -= N * cost
                add entry to G.posts ("00-12")
                if authors[author].time is nil:
                    authors[author].time = NOW
       like:    liker.reps -= N   (must afford it)
                tax + split to target
       dislike: liker.reps -= N
                tax + split (negative) to target
                update the revoke channels
    3. gate: author affords the cost (Rule 4.a)
       -> ACCEPTED or BLOCKED/beg
    4. cap: clamp all authors at `max`
    5. snapshot G, then commit the action file
```

Apply runs BEFORE the commit: a rejected action never
becomes a commit at all.

## Computation

Reputation can be recomputed from scratch by walking
the DAG in `--date-order` and replaying each action
file:

```
authors = pioneers(genesis)
for each commit after genesis in git log --date-order:
    process time effects (discount, consolidation)
    act = the commit's actions/ab/<aid>.lua
    if act.action is 'like' or 'revoke':
        liker.reps -= abs(act.n)        (full magnitude)
        tax = abs(act.n) * 10 / 100
        delivered = act.n - sign(act.n) * tax
        if act.post:
            post_author.reps += delivered / 2
            post.reps        += delivered / 2
        elif act.author:
            target_author.reps += delivered
    elif act.action is 'post':
        author.reps -= cost
        add to time tracking
    (skip merge commits: pure topology, empty diff)
    cap all authors at `max`
```

## Git Representation

Every action — post and vote alike — is one commit
whose entire diff is its own action file:

```
actions/ab/<aid>.lua
    { action='like', backs={...}, sign=<pubkey>,
      time=<ts>, post=<aid>, n=450 }
```

- **no trailer**: classification is structural (the
  commit adds an action file; `action` names the kind)
- **empty commit message**: no user text in undeletable
  objects
- **payload out of the tree**: a vote's `--why` is its
  optional payload, anchored at `refs/payloads/<aid>`
- **signed** by the caster's key (required for
  authorship)

This makes votes first-class blocks in the DAG,
synchronized via the same git fetch/merge mechanism as
regular posts.

## CLI Commands

```
freechains chain <alias> like <N> <target> <id> --sign <key> [--why <text>]
freechains chain <alias> dislike <N> <target> <id> --sign <key> [--why <text>]
freechains chain <alias> reps <pubkey-or-aid>
```

`reps` prints raw units (no truncation): a pioneer of a
1-pioneer chain reads `30000`.

## Test: Time Flow Example

1-pioneer chain, KEY has 30000 reps.

```
t=0:    KEY posts P1 (signed)
        G.authors: KEY={reps=29000} (-1000)
        G.posts:   P1={author=KEY, time=0, maturity="00-12"}

t=0:    KEY posts P2 (signed)
        -- scan "00-12": P1 discount recomputed
        --   subsequent_reps: KEY posted after P1, KEY has 29000
        --   total_reps: 29000
        --   ratio = 29000/29000 = 1.0 >= 0.5
        --   discount = 0
        --   NOW(0) >= 0+0 -> refund P1
        G.authors: KEY={reps=29000} (29000+1000-1000)
        G.posts:   P1={..., maturity="12-24"}
                   P2={author=KEY, time=0, maturity="00-12"}

t=0:    KEY posts P3 (signed)
        -- scan "00-12": P2 discount = 0 (ratio=1.0) -> refund
        -- scan "12-24": P1 time=0, NOW=0 < 0+86400 -> wait
        G.authors: KEY={reps=29000} (29000+1000-1000)
        G.posts:   P1={..., maturity="12-24"}
                   P2={..., maturity="12-24"}
                   P3={author=KEY, time=0, maturity="00-12"}

t=24h:  KEY posts P4 (signed)
        -- scan "00-12": P3 discount = 0 -> refund
        -- scan "12-24": P1 time=0, NOW=86400 >= 86400
        --   authors[KEY].time absent -> grant +1000
        --   authors[KEY].reps += 1000, cap 30000
        --   authors[KEY].time = 0
        -- scan "12-24": P2 time=0, NOW=86400 >= 86400
        --   authors[KEY].time = 0, 0-0 = 0 < 86400
        --   -> no grant (1/day limit), discard
        G.authors: KEY={reps=30000, time=0} (capped)
        G.posts:   P3={..., maturity="12-24"}
                   P4={author=KEY, time=86400, maturity="00-12"}

t=48h:  KEY posts P5 (signed)
        -- scan "00-12": P4 discount = 0 -> refund
        -- scan "12-24": P3 time=0, NOW=172800 >= 86400
        --   authors[KEY].time=0, 0-0=0 < 86400 -> no grant
        --   discard P3
        G.authors: KEY={reps=30000, time=0} (capped)
        G.posts:   P5={author=KEY, time=172800, maturity="00-12"}
```

Observations:
- Posts are effectively free in active chains (discount=0)
- Consolidation grants +`cost`/day, capped at `max`
- Pioneer stays at 30000 despite posting (cost refunded)
- Matches Kotlin test c03/c04 behavior (full reps after posts)

## Related Plans

- [chains.md](chains.md) — chain types and pioneer setup
- [260809-reps.md](260809-reps.md) — parameter review
  (what's good/bad for users) + the pending NO DEBT gates
- [done/260722-bug-reps-debt.md](done/260722-bug-reps-debt.md)
  — vote affordability gate (shipped)
- [280808-redesign.md](280808-redesign.md) — action files,
  snapshots, the storage model above
- [commands.md](commands.md) — CLI command mapping
- [consensus.md](consensus.md) — reputation as validation
  gate
- [layout.md](layout.md) — filesystem layout
- [tests.md](tests.md) — Sections C, M, N test reputation
- [references.md](references.md) — papers, docs, guides

## Done

- [x] Plan: internal/external rep model (1000x) — REVERTED
      by REPS UNITS: one currency, CLI speaks raw
- [x] Plan: 10% tax on likes
- [x] Plan: like/dislike split subcommands
- [x] Plan: self-like allowed
- [x] Plan: variable discount (0-12h, Rule 2)
- [x] Plan: consolidation regrant (+1/day, Rule 1.b)
- [x] Plan: 3 block states (ACCEPTED/BLOCKED/REVOKED)
- [x] Plan: `max` cap (Rule 4.b)
- [x] Plan: revocation threshold (Rule 3.b)
- [x] Tests: cli-like.lua (like command structure)
- [x] Tests: reps.lua (reputation math)
- [x] Impl: like/dislike commands in src/freechains
- [x] Impl: vote affordability gate (no debt)
- [x] Impl: one currency (CLI speaks raw units)
- [x] Impl: state as snapshots, not tree files
      (`.freechains/` and skel deleted)

## TODO

- [x] Impl: post gate (Rule 4.a, presence: `reps > 0`)
- [x] Impl: variable discount engine (Rule 2)
- [x] Impl: consolidation engine (Rule 1.b)
- [x] Impl: `max` cap (Rule 4.b)
- [x] Impl: signing gate (--sign required, --beg bypass)
- [x] Impl: reps command in src/freechains
- [x] Refactor: chain.lua flatten (less nesting)
- [x] Tests: variable discount (0-12h)
- [x] Tests: consolidation (+`cost`/day, 24h)
- [x] Tests: `max` cap
- [x] Tests: gate check (blocked, accepted, unblocked, beg-with-reps)
- [x] Tests: author-targeted likes (cost, gains, like 2, dislike)
- [x] Impl: consensus tie-breaker (hash comparison)
- [ ] Impl: NO DEBT — post gate `reps >= cost`, beg gate
      `reps < cost`, beg-like floor `n >= cost`
      ([260809-reps.md](260809-reps.md); before sync/release)
- [ ] Decide: pioneer floor for large N ([260809-reps.md](260809-reps.md))
- [ ] Decide: exclude the author from `subsequent_reps`
      ([260809-reps.md](260809-reps.md))
- [ ] Tests: bilateral sync (B recv A + bit-equality)
- [ ] Tests: tie-breaker (same-timestamp divergence)
- [ ] Plan: file-op cost model (Rule 5)
- [ ] Impl: file-op count via git diff-tree (Rule 5)
- [ ] Impl: N * `cost` post cost (Rule 5)
- [ ] Impl: fetch/merge file-op validation (Rule 5)
- [ ] Tests: file-op cost (1 file, multi-file)
- [ ] Impl: revocation state (Rule 3.b)
- [ ] Impl: 128 KB size limit (Rule 4.c)
- [ ] Tests: revocation threshold
- [ ] Tests: time flow example (above)
