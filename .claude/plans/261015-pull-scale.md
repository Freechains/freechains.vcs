# Pull cost grows with the chain (26/10/15)

# Context

- found in 2606-sims `p2p/scale.sh` (ia-optim 41a90a6): one chain,
  posts only; post flat (0.09 s), pulls grow with chain size
    - 1-post pull: 0.26 / 0.70 / 1.22 / 4.73 s at 1k/5k/10k/34k
    - noop pull: 0.08 / 0.16 / 0.28 / 1.36 s
- profile at 50k (1-post pull 11.5 s):
    - 2 `git fetch` x ~3.7 s: connectivity check
      `rev-list --objects --stdin --not --all`: `--all` loads all
      ~100k refs (snapshot + payload per post)
    - payload pass ~3.4 s: reads the state, checks the payload
      of EVERY action (cat-file batches), not the new ones

# Fix 1: hide local refs from fetch (main, ia-optim)

- `git_init` (chains.lua): `fetch.hideRefs` for the snapshot
  prefix (main `refs/states/`, ia-optim `refs/local/`) and
  `refs/payloads/`
- git drops hidden refs from the check (`--exclude-hidden=fetch`)
  and from negotiation; what the remote serves is unchanged
- measured at 50k (copy, ia-optim): noop fetch 3.7 -> 0.12 s;
  1-post pull 11.5 -> 3.7 s; payload arrives
- existing chains keep the old config (recreate or set by hand)

# Fix 2: payload pass (won't do: already incremental)

- ia-optim already checks only the affected cids; the full pass
  runs once, when `payloads-missing` does not exist yet
- the 3.4 s was that one-off pass: `scale.sh` copies B from A,
  which never pulled; a 2nd pull on the same copy at 50k:
  0.87 s (fix 1 on), fetches 0.44 + 0.35 s
- so `scale.sh` overstates the 1-post pull: warm B up with one
  pull before timing (2606-sims)
- main: glob fetch `refs/payloads/*` lists every remote payload
  ref, then a loop over all actions: needs ia-optim's explicit-cid
  fetch; known limit, not fixed in main

# Tests

- `tst/bug-fetch-hiderefs.lua` (both): init and clone set
  `fetch.hideRefs` for both prefixes
- fix 2: existing payload/revoke suites; cost via `scale.sh`

# Status

- [x] failing tests (both): fail, then pass with fix 1
- [x] fix 1 main: 45/45 suites (with a `freechains` wrapper on
  PATH: the installed build is ia-optim, hooks call it)
- [x] fix 1 ia-optim: 48/48 suites, guide.sh
- [x] fix 2: won't do (already incremental, see above)
- [ ] rerun `scale.sh` (2606-sims) on the fixed build
