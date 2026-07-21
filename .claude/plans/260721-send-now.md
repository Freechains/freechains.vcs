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

## Pending

- [x] Diagnose (hook drops `--now`; only `sync.lua:454` is affected)
- [x] Confirm consensus is unaffected
- [ ] NEXT: pick option 1 or 2
- [ ] If 1: note the constraint next to the send tests
- [ ] If 2: forward `--now` as a push option + gate it
