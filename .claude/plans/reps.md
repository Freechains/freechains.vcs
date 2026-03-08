# Reputation: Likes, Dislikes, and Pioneers

## Overview

Reputation is a per-author integer tracked per chain.
It is computed by replaying the commit history (likes,
dislikes, posts) and stored in Lua tables inside each
chain repo at `.freechains/reps-authors.lua` and
`.freechains/reps-posts.lua`.
Both files are tracked by git.

## Initial Reputation: Pioneers

Each chain starts with a total of **30 reputation** split
equally among its pioneers:

| Pioneers | Reps each |
|----------|-----------|
| 1        | 30        |
| 2        | 15        |
| 3        | 10        |
| N        | 30 / N    |

Pioneers are listed in the genesis block (`pioneers`
field).
Non-pioneer authors start with **0 reputation**.

Chains without pioneers are fully open — no reputation
gate at all.

### Special chain types

| Type        | Reputation rule                     |
|-------------|-------------------------------------|
| `#` public  | Pioneer-based (30 / N)              |
| `$` private | All holders of shared key = infinite|
| `@` personal| Key holder = infinite               |

## Actions and Costs

### Posting

Each post costs **1 reputation** from the author:

```
post block:  author.reps -= 1
```

If the author's reputation is insufficient, the post is
accepted into the DAG but marked **BLOCKED** (invisible
to consensus).

### Like

A like is a zero-payload commit with an extra header:

```
freechains-like: <target-hash>
```

It transfers `n` reputation from the liker to the target
block's author:

```
Like(n, target):
    liker.reps        -= 1    (cost of posting the like)
    target_author.reps += n   (after 12h maturation)
```

Typical value: `n = 1`.
Higher values (e.g., `n = 2`) are allowed.

### Dislike

A dislike is a zero-payload commit with an extra header:

```
freechains-dislike: <target-hash>
```

It reduces the target author's reputation:

```
Dislike(n, target):
    liker.reps        -= 1    (cost of posting the dislike)
    target_author.reps -= n   (penalty on target)
```

Dislikes are immediate — no maturation delay.

A dislike can include a reason via a `--why` field.

## The 12-Hour Maturation Rule

Reputation gained from likes does **not** materialize
immediately.
It only becomes visible after **12 hours** have elapsed
since the like block's creation.

```
if (now - like.timestamp) < 12h:
    like has no effect yet
else:
    target_author.reps += n
```

This prevents rapid reputation inflation exploits.

### Examples from the Kotlin test suite

| Time    | Event                     | PUB0 | PUB1 |
|---------|---------------------------|------|------|
| 0h      | PUB0 posts (pioneer 30)   | 29   | 0    |
| 0h      | PUB0 likes PUB1's post    | 28   | 0    |
| 11h 59m | (waiting)                 | 28   | 0    |
| 12h 01m | like materializes         | 28   | 1    |
| 24h 01m | second 12h block          | 28   | 2    |

Reputation accumulates per 12-hour window — each window
that passes since the like allows another unit to
materialize.

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
    reps-authors.lua       -- author → reputation
    reps-posts.lua         -- post → like/dislike counts
```

All three files are tracked by git (committed).
If deleted, they can be rebuilt by replaying git history.

### reps-authors.lua

Maps each author's public key to their current reputation:

```lua
return {
    ["ed25519:abc..."] = 28,
    ["ed25519:xyz..."] = 2,
}
```

### reps-posts.lua

Maps posts that have been liked or disliked to their
counts (only rated posts appear):

```lua
return {
    ["a1b2c3d4..."] = { likes = 2, dislikes = 1 },
    ["e5f6g7h8..."] = { likes = 0, dislikes = 3 },
}
```

### Update frequency

Both files are updated on **every commit** (post, like,
or dislike).

## Computation

Reputation is computed by walking the DAG in
`--date-order`:

```
for each commit in git log --date-order:
    if commit is genesis:
        initialize pioneer reps (30 / N)
    elif commit has freechains-like header:
        apply like (with 12h maturation check)
    elif commit has freechains-dislike header:
        apply dislike (immediate)
    elif commit is a regular post:
        author.reps -= 1
    (skip merge-only commits)
```

If the Lua files are deleted, they can be fully
reconstructed by replaying the git history.

## Git Representation

Likes and dislikes are stored as commits with:

- **Empty tree** (no payload — same tree as genesis)
- **Extra header** identifying the target block
- **Signed** by the liker's key (required for authorship)

```
tree 4b825dc...           (empty tree)
parent <HEAD>
author <pubkey> <timestamp>
committer <pubkey> <timestamp>
freechains-like: <target-hash>

```

This makes likes/dislikes first-class blocks in the DAG,
synchronized via the same git fetch/merge mechanism as
regular posts.

## Self-Interactions

- **Self-like**: rejected (cannot boost own reputation)
- **Self-dislike**: allowed — payload becomes empty,
  author's reps drop to 0

## Related Plans

- [chains.md](chains.md) — chain types and pioneer setup
- [commands.md](commands.md) — `like`, `dislike`, `reps`
  CLI mapping
- [consensus.md](consensus.md) — reputation as validation
  gate
- [layout.md](layout.md) — filesystem layout including
  `.freechains/`
- [tests.md](tests.md) — Sections C, M, N test reputation
