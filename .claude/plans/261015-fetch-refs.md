# Fetch cost grows with local refs (26/10/15)

# Context

- found in 2606-sims `p2p/scale.sh` (ia-optim, after hideRefs):
  1-commit pull 0.50 s at 34k, 1.40 s at 100k (linear again)
- profile at 100k (1-commit pull 1.2 s): 2 fetches x ~0.5 s
- local refs: ~1 snapshot + ~1 payload ref per post (200k)
- one fetch (0.54 s), git 2.43, each step over all local refs:
    - startup ~80 ms: load `packed-refs` (19 MB)
    - `mark_complete_local_refs` ~165 ms: parses every ref,
      `hideRefs` does not apply
    - negotiator setup ~150 ms: every ref as a "have" tip
    - consume ~50 ms
- `hideRefs` (261015-pull-scale) only covers the connectivity check

# Fix 1: negotiation tip (main, ia-optim)

- `--negotiation-tip=refs/heads/main` on the sync fetches
  (commits + begs, payloads)
- measured at 100k: one fetch 0.54 -> 0.39 s
- the chain is linear in `main`: its tip is a complete "have" set
- clone (`chains.lua`): fresh repo, no refs, unchanged

# Fix 2: fewer local refs (design, ia-optim)

- still linear: startup + `mark_complete` (~245 ms at 100k)
- snapshots (`refs/local/`): local only, refs just pin them for gc
    - pin by one ref: a commit/tree that indexes the snapshots
    - or keep a floor of snapshots (every K-th), derive the rest
- payloads (`refs/payloads/`): also the wire protocol (refspecs)
    - fetch by oid (`uploadpack.allowAnySHA1InWant`) and pin with
      one index ref
- open: cost of updating the index per post; gc reachability
- decide after fix 1, with a profile at 100k

# Status

- [x] profile at 100k (2606-sims)
- [ ] fix 1 main
- [ ] fix 1 ia-optim
- [ ] fix 2: design
- [ ] rerun `scale.sh` (2606-sims)
