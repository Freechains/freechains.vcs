# Snapshot layout: linear storage, flat op time

- for: freechains implementation (refs/local snapshots)
- from: sims (2606-sims), chat r3 and usenet r5 END keeps
- keep SHA-1 in Lua (C only changes the constant)
- reviewed by freechains-ia (261007-ia-optim), 24/11: OK
    - waits for the user's OK there before implementing
    - base: tick-beg-like (0f43041) not installed yet

# Problem (measured)

- each op rewrites trees that grow with the chain
    - `actions/xx`: N/256 entries (587 at 155k, 45 kB raw)
    - `order`: one tree of N/200 files (778 at 155k)
- `meta.lua` carries the open tick's `posts` list
    - chat: 355 of 830 MB on disk, 38.5% stored whole
    - up to 20 kB raw per snapshot (316 cids at 120k)
- last `order` chunk (200 cids, 8 kB) rewritten per op
- raw bytes per snapshot, chat: 24 kB (10k) -> 106 kB (155k)
- pure-Lua sha1 is 82-88% of Lua work per op
    - post: 2.5M -> 10.7M instr; sync ff: 7.3M -> 48.2M
- so: op time O(N), storage O(N^2)

# Changes

- actions: 2-level shards
    - `apath`: `actions/xx/yy/<cid>.lua` (cid[1:2], cid[3:4])
    - `state.lua` shard code assumes 1 level in ~6 places:
      `shards_all`, `all`, `members_all`, `^(%a+)/%x%x$`
      (858, 1060), 935
    - same depth for members (`members/xx/yy`): one code path
- order: smaller chunks, 2-level dirs
    - `ORDER_K` 200 -> 50
    - `opath`: `order/NNN/NNNNN.txt` (i // 100, i)
    - `sync.lua` hardfork: `ls-tree -r <ref> order/` (42),
      pattern with the extra dir (45)
    - read path: check `state.lua` 1333, 1383
- tick: no cid list in `meta.lua`
    - `tick.posts` (cids) -> `tick.charged` (pub -> count)
    - `close`: bump each pub by count * cost (same reps:
      `bump` has no cap; members are independent)
    - `needs`: no fetch of the tick's posts (pubs only)
    - `advance`: empty-tick test uses `charged`
    - initial tick (`chains.lua` 240): `charged = {}`
    - `needs` still returns the `posted` cids
    - `tick_post`: count instead of append (also for
      admitted begs)
    - keep `posted` (first cid per pub, for credit)
    - keep `acting`
- keep SHA-1 and loose-object writer as they are

# Compatibility

- snapshots are local (`refs/local`), not synced
- old repos: no rebuild (sims rerun from scratch)
    - layout field in `meta.lua`: clear error on old repos
- consensus, wire and refs/payloads unchanged

# Validation

- same order and reps, old vs new layout, same base
  commit (tick-beg-like changes reps by itself)
    - usenet r5 final: 33,814 actions
    - chat r3 final: 155,528 actions
- existing freechains tests pass, `tst/cli-tick` included

# Expected (sims layout test, chat END, same packing)

- packed total: 29% of today's layout (1,335 -> 382 MB)
- per snapshot packed: 1.80 -> 2.26 kB (10k -> 155k)
- raw per snapshot ~flat: about 14 -> 28 kB
- sha1 work per op ~flat, about 3.5x less at 155k
- test used `posts` as a count and 8-hex author keys
    - plan keeps full keys and per-pub counts: a bit more

# After the change (sims side)

- storage: replay each END chain on one peer
- op time: post/ff bench on copies at 10k..155k
- p2p reruns only if the paper needs new op times
    - usenet r5 ~50 h, chat r3 ~200 h

# Status

- [x] plan copied from 2606-sims, user OK (26/11/24)
- [x] step 1: tick.charged (rules.lua, chains.lua)
- [x] step 2: order chunks (state.lua, sync.lua)
    - read still lists every chunk (`ls-tree -r`): ~2.8 ms Lua
      at 155k, about one more git spawn; kept simple
- [x] step 3: actions/members 2-level shards (state.lua)
    - `listing`: dir ids from contents, deepest first
    - `shards_all`: `ls-tree -r -t` (2nd-level trees)
- [x] step 4: `layout=2` in meta.lua, ERROR on other
- [x] tests: 49/49 suites, guide.sh (snapshot: xx/yy, layout=2,
  charged)
- [x] installed (26/11/24, uncommitted worktree, `0f43041` +)
- [ ] old vs new on the END chains (sims)
