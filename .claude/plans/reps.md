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

### Like / Dislike (split subcommands)

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

## The 12-Hour Maturation Rule

See [time.md](time.md) for full details on time source
(committer timestamp), trust model, and validation.

A post must sit in the DAG for **12 hours** before it is
considered settled. During this window the community can
evaluate the post and potentially dislike it.

This gives the community a guaranteed reaction window
before content becomes part of settled consensus.

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
    likes/                 -- like payload files (created at chain init)
    reps/
      authors.lua          -- author → internal reputation
      posts.lua            -- post → internal reputation
```

The `chains add` command calls `skel()` to create all
directories and default files before copying genesis input.
`reps/authors.lua` and `reps/posts.lua` default to
`return {}`.
Genesis input's `reps/authors.lua` overwrites the default
(pioneers get initial reps).

All three files are tracked by git (committed).
If deleted, they can be rebuilt by replaying git history.

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

### Update frequency

Both files are updated on **every commit** (post or
like).

## Computation

Reputation is computed by walking the DAG in
`--date-order`:

```
load reps/authors.lua from genesis commit
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
freechains chain <alias> like <N> <target> <id> --sign <key> [--why <reason>]
freechains chain <alias> dislike <N> <target> <id> --sign <key> [--why <reason>]
freechains chain <alias> reps <pubkey-or-hash>
```

`reps` returns the external integer (internal // 1000,
truncated toward zero).

## Fork Votes and Reputation

When a branch divergence triggers voting (see merge.md),
votes are weighted by the author's reputation **in the
common prefix** — reputation computed up to the fork
point, not beyond it. This ensures:

- Only authors with established standing can influence
  the fork decision
- Reputation earned after the fork (in either branch)
  doesn't affect the vote
- The vote weight is deterministic — all peers compute
  the same prefix reputation

A vote is a signed commit (like a dislike) that references
the fork point and declares a branch preference. The cost
is the same as a dislike (1 rep). The weight is the
author's prefix reputation at the fork point.

## Related Plans

- [chains.md](chains.md) — chain types and pioneer setup
- [commands.md](commands.md) — CLI command mapping
- [consensus.md](consensus.md) — reputation as validation
  gate
- [merge.md](merge.md) — fork votes weighted by prefix
  reputation
- [layout.md](layout.md) — filesystem layout including
  `.freechains/`
- [tests.md](tests.md) — Sections C, M, N test reputation

## Done

- [x] Plan: internal/external rep model (1000x)
- [x] Plan: 10% tax on likes
- [x] Plan: like/dislike split subcommands
- [x] Plan: self-like allowed
- [x] Tests: cli-like.lua (like command structure)
- [x] Tests: reps.lua (reputation math)
- [x] Impl: like/dislike commands in src/freechains
- [x] Impl: .freechains/likes/ created at chain init
- [x] Impl: skel() creates full .freechains/ skeleton
- [x] Impl: reps/ nested dir (authors.lua, posts.lua)

## TODO

- [ ] Impl: reps command in src/freechains
- [ ] Impl: reputation engine (update reps files on
  commit)
- [ ] Impl: 12h maturation rule
- [ ] Tests: 12h maturation
- [ ] Tests: author-targeted likes
