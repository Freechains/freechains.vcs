# Time in Freechains

## Time Source: Committer Timestamp

Every git commit has two mandatory timestamps:

```
author <name> <email> <timestamp> <tz>
committer <name> <email> <timestamp> <tz>
```

Freechains uses the **committer timestamp** (`%ct`) as the
canonical time source.

### Why committer over author?

In freechains there's no rebasing or cherry-picking — commits
are created once and replicated as-is.
Both timestamps should always be identical in practice.
Committer timestamp is chosen because it reflects when the
commit entered the DAG, which is what the 12h maturation
rule cares about.

### Extraction

```bash
git log --format='%ct' -1 <hash>     # unix timestamp
git cat-file commit <hash>           # raw, parse committer line
```

### Other time sources

- **Filename timestamps** (`os.time()` in filenames like
  `post-<t>-<hash>.txt` and `like-<t>-<hash>.lua`): ensure
  unique filenames, not used for logic.
- **GPG signature timestamps**: only present on signed
  commits, not a general source.

## Trust Model: Forgeable but Tamper-Proof

Timestamps are **self-reported** at creation — a node can
set any value it wants via `GIT_COMMITTER_DATE`.

However, once a commit is part of the DAG, its timestamps
are **immutable** — changing them would change the commit
hash, breaking all references to it.

**Forgeable at creation, tamper-proof after.**

## The Problem: No Git Restrictions

Git imposes **no restrictions** on timestamps:

- A child commit can have an earlier date than its parent
- Dates can be set to 1970 or 2099
- `--date-order` traversal becomes nonsensical with forged
  timestamps

This enables exploits:

- **Backdating** a like to bypass the 12h maturation rule
- **Future-dating** a like so it appears mature immediately
  to all receivers

## Timestamp Validation (planned)

The consensus engine should validate timestamps during
fetch/merge. Possible rules:

### 1. Monotonic relative to parent

```
commit.timestamp >= parent.timestamp
```

Ensures time never goes backwards within the DAG.

### 2. Not in the future

```
commit.timestamp <= receiver.local_time + tolerance
```

Prevents future-dating exploits.

**Default tolerance: 1 hour (3600 seconds).**
Configurable per chain via `genesis.lua` field `tolerance`
(in seconds). See [genesis.md](genesis.md).

1 hour is negligible relative to the 12h maturation window
(< 9%) and accommodates nodes with poor clock sync.

### 3. Both combined

Ensures a sane timeline: monotonically increasing and
bounded by the receiver's clock.

## 12-Hour Maturation Rule

Reputation gained from likes does **not** materialize
immediately.
It only becomes visible after **12 hours** have elapsed
since the like commit's committer timestamp.

```
if (now - like.committer_timestamp) < 12h:
    like has no effect yet
else:
    apply like effects
```

This prevents rapid reputation inflation exploits
(A likes B, B immediately spends new reps to like C, etc.).

## Status

- [x] Decision: committer timestamp as time basis
- [ ] Impl: timestamp validation in consensus
- [ ] Impl: 12h maturation rule using committer timestamp
- [ ] Tests: forged timestamps rejected
- [ ] Tests: 12h maturation

## Related Plans

- [reps.md](reps.md) — reputation system, 12h rule usage
- [consensus.md](consensus.md) — fetch validation pipeline
