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

- left at 100k: ~0.25 s per fetch (startup + `mark_complete`),
  ~half snapshot refs, ~half payload refs
- the worry is small: 1 s pull at 100k, ~5 ms more per 1k posts;
  clone (47 min at 100k) is the larger cost
- A: snapshots off refs (half the cost, local only)
    - index in files (`local/<xx>`: cid -> tree), not refs
    - gc pin only at sweep (gc is manual): one commit whose tree
      holds the live snapshots, at `refs/local/pin`
    - discard drops index entries; next sweep reaps them
    - `state.lua` lookups (`REF()`) read the index
- B: payloads off refs (the other half, wire protocol)
    - fetch blobs by oid (`uploadpack.allowAnySHA1InWant`)
    - pin like A; post/like/sync/discard drop their ref updates
    - changes what peers serve and ask: old/new peers mismatch
- suggest: A only if a larger scale run needs it; B won't do

# Status

- [x] profile at 100k (2606-sims)
- [ ] fix 1 main: skipped for now (user, 26/10/15)
- [x] fix 1 ia-optim: sync.lua 174, 556 (48/48, guide.sh: user)
    - installed, at 100k: fetches 0.52 + 0.59 -> 0.38 + 0.43 s;
      1-commit pull 1.22 -> ~1.0 s; noop 0.27 s (unchanged)
- [ ] fix 2: decide (A later or won't do; B won't do)
- [ ] rerun `scale.sh` (2606-sims)
