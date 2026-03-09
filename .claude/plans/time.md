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

## Read-Time vs Write-Time Validation

The 12h maturation rule introduces a subtle problem:
**validation depends on when a node receives the commit,
not just on the DAG content itself.**

### The Problem: Temporary Divergence

Consider a like commit with committer timestamp `T`:

1. **Node A** fetches at `T + 12h + 1min` — 12h window has
   passed — the like's reputation effect is visible →
   a post that depends on that reputation is **accepted**
2. **Node B** fetches at `T + 12h - 1min` — 12h window has
   NOT passed — the like has no effect yet → the same
   post is **rejected** (author lacks reputation)
3. **Later**, Node B retries the fetch — now `T + 12h` has
   passed — the post is **accepted**
4. A and B converge to the **same state**

### Analysis

The system is **eventually consistent** — not permanently
divergent. Given the same DAG content, all nodes converge
once enough wall-clock time has passed. But during the
disagreement window:

- **Confusing UX** — a fetch fails, but retrying later
  silently succeeds with the exact same data
- **Cascading disagreement** — further posts building on
  the disputed commit also diverge temporarily
- **Retry semantics are implicit** — the protocol doesn't
  specify that nodes should retry rejected fetches, or
  how often

### Why This Is Acceptable

- **Git fetch is unconditional** — `git fetch` transfers
  all objects regardless of freechains validation. Even if
  the freechains layer rejects a commit at validation time,
  the git objects are already local. On the next pull/fetch,
  they don't need to be re-transferred — the node just
  needs to re-evaluate them once enough time has passed.
  This guarantees convergence at the git level.
- The disagreement window is bounded (at most ~12h)
- The DAG is content-addressed — once time passes, all
  honest nodes agree on the same state
- The alternative (write-time-only validation) would
  allow gaming: a node could claim "I received this like
  13h ago" with no way to verify
- Backdating attacks are bounded to ≤1h (the tolerance),
  which is < 9% of the 12h window

### Design Decision

**Read-time validation is the correct choice** despite the
temporary non-determinism, because:

1. It cannot be forged (uses receiver's local clock)
2. Convergence is guaranteed (same DAG → same result,
   given enough time)
3. The bounded disagreement window is a smaller problem
   than the unbounded gaming that write-time-only would
   allow

## 7-Day Hard Fork Threshold

The hard fork rule (see [consensus.md](consensus.md)) uses
a **7-day** time threshold. If two concurrent branches are
separated by more than 7 days of elapsed time, syncing them
results in permanent consensus divergence — each peer keeps
its own local ordering.

### Timing Implications

- The 7-day window is measured from committer timestamps
  in the DAG, not wall-clock time at sync
- A node that stays offline for >7 days and then syncs will
  trigger a hard fork if the remote also posted during that
  window
- Timestamp forgery interacts with this rule: a node could
  backdate or future-date commits to manipulate whether the
  7-day threshold is crossed
- The 1-hour tolerance (Section "Not in the future") bounds
  future-dating to <1h — negligible vs 7 days (<0.6%)
- Backdating is harder to prevent but is bounded by the
  monotonic parent rule (commit.timestamp >= parent.timestamp)

### Relationship to Other Time Rules

| Rule             | Window  | Purpose                          |
|------------------|---------|----------------------------------|
| Future tolerance | 1 hour  | Bound clock drift                |
| 12h maturation   | 12 hours| Prevent reputation inflation     |
| Hard fork        | 7 days  | Freeze consensus, force diverge  |

All three rules depend on committer timestamps but operate
at different scales. The hard fork threshold is the largest
and defines the boundary of consensus convergence.

## Status

- [x] Decision: committer timestamp as time basis
- [ ] Impl: timestamp validation in consensus
- [ ] Impl: 12h maturation rule using committer timestamp
- [ ] Tests: forged timestamps rejected
- [ ] Tests: 12h maturation

## Related Plans

- [reps.md](reps.md) — reputation system, 12h rule usage
- [consensus.md](consensus.md) — fetch validation pipeline
