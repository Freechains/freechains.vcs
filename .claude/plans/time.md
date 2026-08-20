# Time in Freechains

## Time Source: The Action File

Every action carries its own `time` field, an integer unix
timestamp written by its author:

```lua
return {
    ["action"] = "post",
    ["time"] = 1780088002,
    ...
}
```

That field is the canonical time source.

### Why not the commit dates

Both git dates are pinned to `@0 +0000` on every commit
(`freechains.lua:227`), so they carry no information at all.
Neutral dates are what make the genesis commit reproducible:
the creator and a cloner hash the same bytes.
Time therefore lives in the action file, which is signed, so
it is covered by the commit signature like any other field.

### Extraction

```lua
ACTION.read(true, aid).time      -- replay and hardfork
env.time                         -- inside apply()
```

### Other time sources

- **`CMD.now`** (`--now` or `os.time()`): the local clock.
  Read in exactly 3 places, all of them writers or queries:
  `post.lua:51,60`, `like.lua:98,112`, `reps.lua:5`; plus
  the `too new` bound in `rules.lua`.
- **SSH signature timestamps**: not extracted, not used.

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
commit.timestamp >= parent.timestamp - tolerance
```

Ensures time never goes significantly backwards within the
DAG.
**Default tolerance: 1 hour (3600 seconds)** — same as the
future tolerance.
Accommodates clock drift between nodes that post
sequentially on the same chain.

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

Ensures a sane timeline: monotonically increasing (within
tolerance) and bounded by the receiver's clock. Both rules
share the same 1-hour default tolerance.

## 12-Hour Maturation Rule

The 12h variable discount period is specified in full in
[reps.md](reps.md) (Rule 2). From the timestamp
perspective: the action's own `time` marks when the post
entered the DAG, and the discount window is measured from
that point.

## Read-Time vs Write-Time Validation

The 12h maturation rule introduces a subtle problem:
**validation depends on when a node receives the commit,
not just on the DAG content itself.**

### The Problem: Temporary Divergence

Consider a post whose action file says `time = T`:

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
a **7-day** time threshold. It is measured as the SPAN of
the commits exclusive to the local branch
(`git rev-list rem..loc`): newest minus oldest. When that
span reaches 7 days the local branch REFUSES to merge
(`ERROR : chain sync : hard fork`), so the divergence is
permanent: the entrenched peer keeps its own ordering and
never absorbs the remote's posts.

Note this is NOT the age of the fork point. Idling after a
fork adds no independent history and must not buy
entrenchment; the branch has to produce commits at both
ends of the window.

### Timing Implications

- The 7-day window is measured from the action files' `time`
  in the DAG, not wall-clock time at sync
- The span is read as max-minus-entry over the window, not
  from the last entry: consensus order is not chronological
- The verdict is never replayed: an entrenched branch does
  not merge, so no merge commit encodes a rule-1 decision.
  Determinism is therefore no longer required here — a
  wall-clock rule (`now - oldest(exc)`) becomes possible,
  and would fix the "post once, then idle" blind spot below
- A fast-forward is never refused (`exc` is empty)
- A node that stays offline for >7 days does NOT trigger a
  hard fork by itself: with no commits of its own, its span
  does not grow. It must commit at both ends of the window
- Every commit kind counts, including the `merge`/`state`
  pair a `sync recv` writes: rule 1 protects this branch's
  ORDERING, and those commits are where the ordering lives
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
|                  | (span)  | span of the branch's own commits |

All three rules depend on the action files' `time` but operate
at different scales. The hard fork threshold is the largest
and defines the boundary of consensus convergence.

## Status

- [x] Decision: the action file's `time` is the basis
- [x] Impl: `too old`, bounded by the DAG (`backs`)
- [x] Impl: `too new`, bounded by MY clock (`CMD.now`)
- [x] Both run in `apply`, so post and replay share them
- [x] Tests: `err-post.lua`, `err-like.lua`

No separate fetch-time hook was built: `apply` already runs
on every replayed action, which is exactly the fetch path.

### Left over

- [ ] `threats.md`: record future-dating as its own threat
- [ ] revisit `260818-prune.md` P2 (time axis of the window)

## Later: 12h Maturation (depends on consensus engine)

- [ ] Impl: 12h maturation rule using the action's `time`
- [ ] Tests: 12h maturation
- Requires DAG-walking reputation recomputation engine
- See [reps.md](reps.md) for maturation details

## Related Plans

- [reps.md](reps.md) — reputation system, 12h rule usage
- [consensus.md](consensus.md) — fetch validation pipeline
- [hardcoded.md](hardcoded.md) — all hardcoded settings
