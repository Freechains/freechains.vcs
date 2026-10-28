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
- revised (26/10/28, paper session): do A and B, rerun sims ok
    - A alone keeps the growth (payload half)
    - B': single `refs/payloads` -> tree `{ xx/<cid> -> blob }`,
      fetch wanted blobs by sha (`blob` field of the action),
      `uploadpack.allowReachableSHA1InWant` on the remote
    - A': single `refs/local` -> tree `{ xx/<cid> -> snapshot }`
    - one fetch per sync if possible (commits + payload shas)
    - measure first: isolated 1-commit pull on the kept 5k/33k
      peers (2606-sims `.freechains-keep/usenet-full-mix-churn-r2-*`)
- profile on the full usenet chain (2606-sims r2-final, 26/10/21):
    - 33.8k posts, 73k local refs: 39k snapshots (54%), 34k
      payloads; `packed-refs` 6.8 MB
    - 1-commit pull 0.46 s isolated (sim log ~1 s: 2 lanes on
      one disk, multi-commit pulls)
    - fetches 0.165 + 0.199 s; freechains + other git ~0.1 s
    - per fetch: `mark_complete_local_refs` ~0.07 s, remote
      `upload-pack` ~0.11-0.13 s (also reads all its refs)
    - A: ~0.46 -> ~0.35 s at this size; growth stays (payloads)
- storage on the same chain (26/10/22): S1 gc'd 154 MB; snapshots
  96 MB (39k trees, 1.5 GB raw), payloads ~35 MB, commits 14 MB
    - snapshots are the overhead (~5x the gzip corpus); fewer
      kept snapshots would cut storage and the ref scan (A)

# Measurements 5k vs 33k (26/10/28, paper session)

- copies of kept S1 (`p00`) and L45 (`p58`), usenet r2, isolated,
  `io.popen` tracer per git subcommand, warm and cold page cache
- post: 0.05 s at 0k, 0.10-0.16 s at 5k and 33k (flat, cold same)
- sync 1-3 commits: 0.22-0.39 s at 5k, 0.83-1.06 s at 33k
    - two fetches: 0.09-0.13 s at 5k, 0.74-0.88 s at 33k
      (main+begs ~0.31 s, payloads ~0.35 s at 33k)
    - Lua CPU ~0.05-0.10 s at both sizes
    - noop sync: 0.06-0.08 s at 5k, 0.24-0.33 s at 33k
- trace2 of one fetch, 5k -> 33k: `mark_complete_local_refs`
  0.017 -> 0.161 s, `consume_refs` 0.011 -> 0.060 s
- refs: 11k at 5k, 73k at 33k; loose objects 36 vs 4.5k
- sim post growth (0.08 -> 0.12 s mean) is lane contention: chat
  run per 5k slice is back to 0.085 s at 30k (sims session)

# Status

- [x] profile at 100k (2606-sims)
- [ ] fix 1 main: skipped for now (user, 26/10/15)
- [x] fix 1 ia-optim: sync.lua 174, 556 (48/48, guide.sh: user)
    - installed, at 100k: fetches 0.52 + 0.59 -> 0.38 + 0.43 s;
      1-commit pull 1.22 -> ~1.0 s; noop 0.27 s (unchanged)
- [ ] fix 2: A' + B' (single tree refs), see revised bullets
    - [ ] measure isolated 1-commit pull on kept 5k/33k peers
    - [ ] rerun usenet sim (user ok, 26/10/28)
- [ ] rerun `scale.sh` (2606-sims)
