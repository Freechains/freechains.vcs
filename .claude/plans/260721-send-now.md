# Plan: `send` path is not time-deterministic (hook drops `--now`)

## Context

Split from `done/260721-bug-push.md`, found while fixing the
non-fast-forward `sync send` bug.

## Finding

`--now` is the determinism knob: it sets `CMD.now` and `CMD.git`, which
pin `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE`
(`src/freechains.lua:206-213`).
Without it, both fall back to `os.time()`.

`lua/freechains/hooks/pre-receive:41-44` builds the receiver's command
with only `--root`, the chain and the url, never `--now`.
So on the send path the receiver's `sync recv` always runs with
`CMD.git = ""`.

| path            | receiver's recv    | state commit date |
|-----------------|--------------------|-------------------|
| `recv --now=N`  | inherits `N`       | `N`               |
| `send --now=N`  | hook, no `--now`   | wall clock        |

The affected commit is the final state commit,
`src/freechains/chain/sync.lua:454`.
The scratch merge commits at `sync.lua:399` live on a detached HEAD and
are discarded, so they never leak.

## Not a protocol bug

Consensus is unaffected: the winner comes from commit dates through
`NOW(oct)` (`src/freechains/chain/common.lua:5`), never from `CMD.now`.
In production both paths use `os.time()` anyway.

## Cost

Test determinism only.
A suite running at `--now=1000..10000` gets a real timestamp injected
into the merge commit, so everything downstream reading `NOW(tip)`
(rep decay, the 12h rule) sees a decades-long gap.

`tst/consensus.lua` Test 1 passes only because its assertions stop at
file content and post counts.
The `no wall-clock timestamps` assertion in `tst/cli-send.lua` step 5
works because it drives a direct `recv`; the same assertion after a
`send` would fail today.

## Options

1. Won't do (recommended).
   `--now` is a test/debug flag, and a receiver has no business
   trusting the sender's clock.
   Document that send-path tests must not assert timestamps.
2. Forward `--now` as a push option.
   The hook already parses `GIT_PUSH_OPTION_*` for `freechains=true`
   and `url=`, so it is cheap.
   But it lets a remote peer dictate local commit dates unless gated to
   tests, which is a footgun for a small test convenience.

## Reproduced

`tst/cli-send.lua` Step 8 (divergent send + `%at` assertion) fails:
`wall-clock leak: 1784838887` (~Jul 2026).
Confirms only the divergent send path leaks: FF sends create no
receiver commit (`sync.lua:352`), case-4 does (`sync.lua:486`).

## Decision: option 2, ungated

The gate is dropped: the hook honors any `now=` push option.
This is acceptable in the current design because `recv` runs on the
peer as a side effect of `send`: the sender pushes, the receiver's
hook runs `sync recv` fetching back.
Sync is already push-triggered and mutual, so `now=` adds no new
trust boundary that the push itself did not already grant.

Revisit the gate when a real, independent `recv` lands (one that
pulls without a push-triggered hook on the peer).
There a remote peer's `now=` would be trusted with no reciprocal
push, so it must be gated (env flag) or dropped.

## Pending

- [x] Diagnose (hook drops `--now`; only `sync.lua:486` is affected)
- [x] Confirm consensus is unaffected
- [x] Reproduce with a red test (Step 8)
- [x] Pick option 2 (forward `--now`, ungated — see Decision)
- [x] `sync.lua` send: add `-o now=N` when `--now` set
- [x] hook: parse `now=`, append `--now=N` (no gate)
- [x] Cleanup leftovers from the dropped gate (comment + dead `ENV`)
- [ ] NEXT: run `make test`; Step 8 should pass
