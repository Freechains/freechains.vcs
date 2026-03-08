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
`reps-authors.lua`, which is created in the genesis
commit alongside `genesis.lua`.
There is no separate `pioneers` field in genesis —
the initial non-zero entries *are* the pioneers.
Non-pioneer authors start with **0 reputation**.

Chains without pioneers have an empty
`reps-authors.lua` — no reputation gate at all.

### Special chain types

| Type        | Reputation rule                     |
|-------------|-------------------------------------|
| `#` public  | Pioneer-based (30 / N)              |
| `$` private | All holders of shared key = infinite|
| `@` personal| Key holder = infinite               |

## Actions and Costs

### Posting

Each post costs **1 external rep** (1000 internal) from
the author:

```
post block:  author.reps -= 1000
```

If the author's reputation is insufficient, the post is
accepted into the DAG but marked **BLOCKED** (invisible
to consensus).

### Like (unified command)

A like is a zero-payload commit with an extra header:

```
freechains-like: +N <target>
freechains-like: -N <target>
```

Where `<target>` is a post hash or an author pubkey.
The number must have an explicit `+` or `-` sign.

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

## The 12-Hour Maturation Rule

Reputation gained from likes does **not** materialize
immediately.
It only becomes visible after **12 hours** have elapsed
since the like block's creation.

```
if (now - like.timestamp) < 12h:
    like has no effect yet
else:
    apply like effects
```

This prevents rapid reputation inflation exploits.

## Block States

A block's acceptance depends on its author's reputation
at the time of consensus evaluation:

| State   | Meaning                                      |
|---------|----------------------------------------------|
| LINKED  | Author had enough reps; visible in consensus |
| BLOCKED | Author's reps too low; invisible             |

A BLOCKED post can become LINKED if the author later
receives enough likes.
A LINKED post can become BLOCKED if the author receives
dislikes that drop their reputation below the threshold.

## Storage

Reputation state lives inside each chain repo under
`.freechains/`:

```
<chain-repo>/
  .freechains/
    genesis.lua            -- genesis block definition
    reps-authors.lua       -- author → internal reputation
    reps-posts.lua         -- post → internal reputation
```

All three files are tracked by git (committed).
If deleted, they can be rebuilt by replaying git history.

### reps-authors.lua

Maps each author's public key to their internal
reputation:

```lua
return {
    ["CA6391CE..."] = 29000,
    ["78397501..."] = 1350,
}
```

### reps-posts.lua

Maps posts to their internal reputation sum:

```lua
return {
    ["a1b2c3d4..."] = 1350,
    ["e5f6g7h8..."] = -1350,
}
```

### Update frequency

Both files are updated on **every commit** (post or
like).

## Computation

Reputation is computed by walking the DAG in
`--date-order`:

```
load reps-authors.lua from genesis commit
for each commit after genesis in git log --date-order:
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
    (skip merge-only commits)
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
freechains chain <alias> like <+/-N> <target> --sign <key> [--why <reason>]
freechains chain <alias> reps <pubkey-or-hash>
```

`reps` returns the external integer (internal // 1000,
truncated toward zero).

## Related Plans

- [chains.md](chains.md) — chain types and pioneer setup
- [commands.md](commands.md) — CLI command mapping
- [consensus.md](consensus.md) — reputation as validation
  gate
- [layout.md](layout.md) — filesystem layout including
  `.freechains/`
- [tests.md](tests.md) — Sections C, M, N test reputation

## Done

- [x] Plan: internal/external rep model (1000x)
- [x] Plan: 10% tax on likes
- [x] Plan: unified like command (+/- N)
- [x] Plan: self-like allowed
- [x] Tests: cli-like.lua (like command structure)
- [x] Tests: reps.lua (reputation math)
- [x] Impl: like command in src/freechains

## TODO

- [ ] Impl: reps command in src/freechains
- [ ] Impl: reputation engine (update reps files on
  commit)
- [ ] Impl: 12h maturation rule
- [ ] Tests: 12h maturation
- [ ] Tests: author-targeted likes
