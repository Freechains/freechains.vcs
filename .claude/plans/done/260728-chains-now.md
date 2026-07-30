# 260728 — genesis `now.lua` = creation time

## Goal

Give genesis a meaningful `state/now.lua` instead of a hardcoded `0`.
Model genesis as sitting on a virtual ancestor whose time is the local
creation instant.
`0` is the epoch masquerading as "no time"; the creation timestamp is a
real causal floor for the chain.

## Rationale

`now.lua` means "newest time among all ancestors of this commit".
Genesis has no real ancestor, so today it ships the skel default `0`.
The genesis's actual time already reaches descendants through
`TIME(genesis)` inside `PEAKS`, so `0` is not *wrong* — but it is
meaningless as a stored value and surfaces as `1970` when read directly
(e.g. `init.lua:18` `now = PEAK("HEAD")` on a postless chain).

Recording the creation time makes the value self-describing and:

- declares the chain's causal start in the signed genesis tree (the
  genesis hash is the chain id, cloned identically by every peer), so it
  is consensus-safe and immutable.
- is a floor an attacker cannot quietly backdate via the commit `%at`
  (which is pinnable with `-o now`).
- auto-fixes the postless-chain "now = 0" display with no change to
  `init.lua`.

## Safety notes

- The verifier skips roots: `commit()` checks `if mx and PEAK ~= mx`, and
  `ANCS(genesis)` is `nil` (no parents).
  So genesis is free to declare any floor without failing validation.
- Set the stored value to the SAME `CMD.now` used for the genesis commit,
  so `TIME(genesis) == now.lua == creation time` is one coherent value.
  If they diverged with `now.lua > TIME(genesis)`, the first-post
  freshness floor would rise above the commit date and could reject a
  legitimately-later post.

## Files to modify

| File                                          | Place                | Change                                                                 |
|-----------------------------------------------|----------------------|-----------------------------------------------------------------------|
| `src/freechains/chains.lua`                   | `ARGS.add` init flow | After skel copy + `pioneers()`, before `git add` (~line 120): write `state/now.lua` with `return <CMD.now>` via `io.open`/`f:write`, mirroring how `pioneers()` writes `authors.lua`. |
| `lua/freechains/skel/.freechains/state/now.lua` | whole file           | Keep as template (overwritten at add). Reword comment to note the genesis value is the chain creation time; keep `return 0` with an example, matching the authors/posts/order skel style. |

## Skel `now.lua` target (example-style, per user choice)

```lua
-- causal high-water (newest ancestor time)
-- genesis: chain creation time, see `chains add`
return 0   -- e.g. 1785000000
```

## Verification (DO NOT run — ask user)

Tests likely affected by the seed shifting from `0` to a real time:

- `cli-now.lua`, `cli-time.lua` — assert on displayed "now".
- `fork-7-days.lua`, `fork-100-posts.lua` — freshness / time spans.
- `climb-underflow*.lua`, `consensus*.lua` — replay seeds.

Ask the user to run `make tests` after edits; never run them unprompted.

## Open / pending

- Confirm `CMD.now` is the intended pinned creation timestamp in the
  `chains add` context (used elsewhere for skel filenames).
- Decide whether `init.lua:18` should switch `PEAK("HEAD")` ->
  `PEAKS{"HEAD"}` as a follow-up (folds `TIME(HEAD)` into the seed for
  every state tip, not just genesis). Out of scope for this plan unless
  requested.

## Status

- [x] skel `now.lua` reworded (example-style)
- [x] `chains.lua` writes `now.lua = CMD.now` at genesis
- [x] tests run (by user) — all pass
- [x] `guide.sh` verified end-to-end — genesis `now.lua` = creation time
      (e.g. `--now=1780000000`), posts/sync/reps/consensus/hard-fork all OK

## Notes on applied change

- `CMD.now` is `os.time()` by default, or `ARGS.now` when `--now` is
  passed (in which case `CMD.git` pins the genesis commit to the same
  value, so `TIME(genesis) == now.lua` exactly).
- Without `--now`, `now.lua` is the parse-time `os.time()`, a hair before
  the commit `%at`; `PEAKS` maxes `TIME(genesis)` anyway, so the floor is
  the commit time — no gap.
- `luac5.4 -p src/freechains/chains.lua` passes.
