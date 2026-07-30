# Revoke/Like Coupling

Couple the reputation and revocation axes asymmetrically, and
expose the revoke counters.
Base spec: `.claude/plans/done/260721-revoke.md`, `reps.md`.

# Rule

- `like` on a post also counts as an `unrevoke`
    - liking means the post should stay visible
- `revoke` also counts as a `dislike` (already implemented)
- converses are false
    - `dislike` never touches the revoke axis
    - `unrevoke` never credits reps

| op         | caster | post/author reps | `revoke` sum |
|------------|--------|------------------|--------------|
| `like`     | -n     | +n               | +n           |
| `dislike`  | -n     | -n               | --           |
| `revoke`   | -n     | -n               | -n           |
| `unrevoke` | -n     | -- (burn)        | +n           |

- `like` = `unrevoke` + reps credit
- `revoke` = `dislike` + revoke debit
- `unrevoke` only restores visibility, never rewards
- author self-revoke stays free and ungated
    - so it does not act as a dislike

# Channels

- `like` from anyone (including the author) feeds
  `revoke.others`
- `revoke.author` stays exclusive to the author's own
  `revoke`/`unrevoke` (absolute right to be forgotten)
- sums remain commutative and order-independent
    - likes cast before a revoke still count
    - a popular post is unrevokable by the community
    - only the author's channel still hides it

# Command: reps revoke

- post-only axis, so the `post` keyword is implicit
- argument is a post hash

```
$ freechains chain '#chat' reps revoke 4a5b6c7
-3 2        -- author others ; revoked if either < 0
```

- `ext()`-scaled, like the other `reps` outputs

# Tasks

## 1. like counts as unrevoke

| file        | place                | change                        |
|-------------|----------------------|-------------------------------|
| `common.lua`| `apply`, `kind=='like'` | if `T.post` then `r.others += T.n` |

## 2. unrevoke grants no reps

| file        | place                | change                        |
|-------------|----------------------|-------------------------------|
| `common.lua`| `apply`, target credit | skip when `kind=='revoke' and T.n>0` |

## 3. reps revoke

| file            | place        | change                          |
|-----------------|--------------|---------------------------------|
| `freechains.lua`| `cmd.chain.reps` | accept `revoke` target      |
| `reps.lua`      | new branch   | print `author others` (`ext`)   |

## 4. docs

| file           | place        | change                           |
|----------------|--------------|----------------------------------|
| `reps.md`      | revoke axis  | coupling rule + table            |
| `commands.md`  | reps row     | `reps revoke <hash>`             |
| `README.md`    | Moderation   | 4-op table (see below)           |

## 5. README moderation table

- insert after the `revoke`/`unrevoke` intro paragraph
    - before `Charlie` posts the spam
- same 4-row table as in # Rule
- 2 short paragraphs after it:
    - a `like` also lifts a revoke, but not the converse
    - a self-revoke is free, so it is not a dislike

## 6. tests

| file             | test                                   |
|------------------|----------------------------------------|
| `cli-revoke.lua` | `like` lifts a community revoke        |
| `cli-revoke.lua` | `dislike` does not revoke              |
| `cli-revoke.lua` | `unrevoke` grants no reps to the post  |
| `cli-revoke.lua` | `reps revoke <hash>` output            |
| `consensus.lua`  | replay order-independence of the sums  |

# Progress

- [ ] 1. like counts as unrevoke
- [ ] 2. unrevoke grants no reps
- [ ] 3. `reps revoke <hash>`
- [ ] 4. docs
- [ ] 5. README moderation table
- [ ] 6. tests
