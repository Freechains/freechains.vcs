# Sync Follow-ups

Loose ends left by [260724-climb-underflow](done/260724-climb-underflow.md)
(nested-merge replay, hard-fork rule, causal freshness). None of them
blocked that work; each is independent of the others.

Ordered by how much they can bite.

## 1. `list dag` crashes on nested merges

```
lua5.4: src/freechains/chain/list.lua:85: attempt to divide by zero
```

Reproduce: build the `tst/climb-underflow.lua` topology (AW / CW / M1 /
takeover / M2) and run `chain '#cu' list dag`. `list order` is fine, so
this is the renderer only.

`list.lua:29` already warns the `dag` branch is AI-generated and
unreviewed. Worth a read-through beyond the immediate division.

Also affects the README guide: the Hard Forks section cannot show a
`list dag` of the forked state while this stands.

## 2. `tst/reorder-ancient.lua` cannot fail

It drives the sync with `sync send`, so the receiver runs inside the git
pre-receive hook, whose stderr `push` swallows. During the work on
`monotonic` the ancient post was silently DROPPED and the test still
passed -- it only asserts the command succeeded.

Fix: drive it with a direct `sync recv`, or assert the resulting order
rather than the exit status. Same trap applies to any test that pushes.

## 3. Entrenchment cannot see idle time

The hard-fork rule measures the SPAN of my settled order. Nothing in the
DAG records that time passed while I was quiet, so:

- post once, idle a year -> not entrenched
- 99 posts in 6 days, then silence for a month -> not entrenched

A wall-clock rule (`now - oldest`) fixes both, and is now PERMISSIBLE:
since rule 1 refuses instead of merging, the verdict never enters a
merge commit and no peer ever replays it, so it need not be
deterministic.

Blocker: which clock.

| clock      | problem                                              |
|------------|------------------------------------------------------|
| `os.time()`| tests and `guide.sh` drive simulated time via `--now` |
| `CMD.now`  | on the push path the SENDER supplies `-o now=`, so a  |
|            | remote could inflate it and force a peer to entrench  |

So the prerequisite is that the receiver stops taking the sender's `now`
for this decision, which needs its own look: the hook currently relies on
that value to pin the dates of the commits it writes.

## 4. Entrenchment isolates honest absentees

Recorded in [threats.md](threats.md) T1. The refusal fires with no
attacker: any peer away long enough crosses the threshold and then
refuses to reconcile until it pulls first. The availability cost to
honest absentees is arguably larger than the attack it prevents.

Options not yet weighed:
- refuse only when the REMOTE is also entrenched (mutual deadlock only)
- an explicit override (`sync recv --force`) that accepts the reorder
- soften rule 1 into the continuous decay already sketched in
  260723-fork-7day.md

## Not doing (recorded, decided)

- Ordering entries by `(time, hash)` instead of consensus: discards
  reps-consensus. Rejected.
- `max(loc, rem)` timestamps for entrenchment: remote-controlled, so a
  peer could force everyone to fork. Rejected.
- Deep/global common ancestor for `climb`: `meet` re-floors at its own
  `up`, so it does not remove the guards, and it breaks `hardfork`.
  Rejected (measured).

## References

- [done/260724-climb-underflow.md](done/260724-climb-underflow.md)
- [threats.md](threats.md) — T1, T1a, T1b, T2a
- [time.md](time.md) — the time rules and their windows
- [consensus.md](consensus.md) — hard fork rule, settled prefix
