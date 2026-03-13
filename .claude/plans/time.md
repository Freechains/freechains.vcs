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

- **Backdating** a post to bypass the 12h community
  reaction window (T2a)
- **Future-dating** a post to affect consensus ordering
  (T2b)

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

A post must sit in the DAG for **12 hours** before it is
considered settled. During this window the community can
evaluate the post and potentially dislike it.

```
if (now - post.committer_timestamp) < 12h:
    post is not yet settled (reaction window open)
```

This gives the community a guaranteed window to react
to new content before it becomes part of settled consensus.

## Read-Time vs Write-Time Validation

The 12h maturation rule introduces a subtle problem:
**validation depends on when a node receives the commit,
not just on the DAG content itself.**

### The Problem: Temporary Divergence

Consider a post with committer timestamp `T`:

1. **Node A** evaluates at `T + 12h + 1min` — 12h window
   has passed — the post is settled, dislikes on it are
   final
2. **Node B** evaluates at `T + 12h - 1min` — 12h window
   has NOT passed — the post is still in its reaction
   window, reputation effects may differ
3. **Later**, Node B re-evaluates — now `T + 12h` has
   passed — both nodes agree
4. A and B converge to the **same state**

### Analysis

The system is **eventually consistent** — not permanently
divergent. Given the same DAG content, all nodes converge
once enough wall-clock time has passed. But during the
disagreement window:

- **Confusing UX** — evaluation differs depending on
  when the node checks, retrying later gives different
  results
- **Cascading disagreement** — further posts building on
  the disputed post also diverge temporarily
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
- Backdating attacks require offline branches (monotonic
  parent rule prevents arbitrary backdating). Offline
  branches are inherently weakened by consensus ordering
  and subject to reactive dislikes (see T2a in
  threats.md). Past tolerance cannot help — local-first
  design requires accepting old timestamps

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
- [x] Impl: monotonic check at post time (tolerance 1h)
- [x] Tests: monotonic violation rejected

## Next: Fetch-Time Validation Infrastructure

The future check (`commit.ts <= receiver.now + tolerance`)
is only meaningful at fetch time — at post time the commit
timestamp equals local time, so the check is trivially true.

Steps:
- [ ] Build fetch-time validation hook (pre-merge-commit
  or post-fetch script that walks incoming commits)
- [ ] Future check: reject incoming commits with
  `commit.ts > local_now + TOLERANCE`
- [ ] Monotonic check on incoming commits (reuse same rule)
- [ ] Tests: future-dated remote commit rejected
- [ ] Tests: monotonic violation in fetched commit rejected

## Later: 12h Maturation (depends on consensus engine)

- [ ] Impl: 12h maturation rule using committer timestamp
- [ ] Tests: 12h maturation
- Requires DAG-walking reputation recomputation engine
- See [reps.md](reps.md) for maturation details

## Related Plans

- [reps.md](reps.md) — reputation system, 12h rule usage
- [consensus.md](consensus.md) — fetch validation pipeline
- [hardcoded.md](hardcoded.md) — all hardcoded settings
