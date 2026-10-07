# Goal

- `sync recv` cost flat in the chain size, as `post` is
- a pull pays only for what it brings and what that touches
- branch: 260914-tree-trash ONLY (main: whole-state blobs, a
  read is O(chain) anyway; not worth it there)
- then the sims rerun everything on this build
  (`/x/papers/2606-sims/`)

# Evidence (26/10/07, tree-trash + bug-winner fix, 41495d5)

- found by the P2P replays in `/x/papers/2606-sims/p2p/`
  (59 peers, ~58 pulls per action, chat corpus)
    - post: flat, ~0.19-0.20 s from 250 to 2,000 actions
    - fast-forward pull, avg per 250 actions: 0.36, 0.51,
      0.57, 0.76, 0.67, 0.88, 0.89, 1.01 s (~+0.4 s per
      1,000 actions; the minimum rises too: 0.13 -> 0.63)
    - single-peer runs never pull: they could not show it
- profile of one pull (instrumented scratch copy of
  `sync.lua`; receiver at ~2,372 actions; 1 new post)

    - 1. `git fetch` main: 0.18 s (new objects)
    - 2. rev-parse / rev-list / merge-base: 0.03 s (~nothing)
    - 3. `CONSENSUS.state(rem)`, the new commit: 0.11-0.16 s
      (new actions)
    - 4-5. winner, replay: 0.01 s (forks)
    - 6. `hardfork` + `update-ref HEAD`: 0.18-0.20 s (order,
      7-day window)
    - 9. `STATE.read` + `STATE.all`: 0.42-0.51 s (WHOLE chain)
    - 10. revoked loop + fetch payloads: 0.21-0.27 s (WHOLE
      chain)
    - 11-12. for-each-ref, payload loop: 0.01 s (whole chain)
    - total: 1.25-1.33 s
- a pull with NOTHING new still costs 0.98 s (fetch 0.15,
  `STATE.all` 0.56, payload fetch 0.19)
- a post at the same size: 0.21 s

# Evidence after fix 2 (26/10/07, f271bee, sims)

- scratch copy of the installed `sync.lua` with timers; copies
  of a chat peer at 2,950 actions (swept); 1 new post per pull;
  idle machine (the "before" profile ran with the sim busy)
    - 1. `git fetch` main: 0.10-0.11 s
    - 2. checks: 0.02 s
    - 3. `CONSENSUS.state(rem)`, the new commit: 0.13-0.17 s
    - 4-5. winner, replay: 0.00-0.01 s
    - 6. `hardfork` + `update-ref HEAD`: 0.03-0.04 s (was
      0.18-0.20 at 2,372 actions)
    - 9. `STATE.read` + `STATE.all`: 0.27-0.30 s
    - 10-12. payload pass: 0.12-0.13 s
    - total: 0.73-0.76 s (was 1.25-1.33)
- nothing new: 0.56 s (was 0.98); a post: 0.21 s (same)
- only step 6 is fix 2's: steps 1, 9, 10-12 also ran faster
  here (idle machine, swept receiver)
- left for fix 1: steps 9 + 10-12 = 0.40-0.43 s (~55% of a
  pull), also when nothing is new; expected pull after fix 1
  ~0.3 s (fetch + apply + checks)

# Evidence after fix 1 (26/10/07, f271bee + fix 1 staged)

- same method, no timers: chat peer at 2,950 actions, swept
    - pull, 1 new post: 0.79 (cold) / 0.49 / 0.51 s (fix 2
      alone: 0.73-0.76)
    - pull, nothing new: 0.17 s (was 0.56)
    - post: 0.22 s (same); orders equal after the pulls
- still above the expected ~0.3 s: profile the remainder

# Cause 1: payload anchors over all actions (`sync.lua:264`)

- every pull loads every action (`STATE.read` + `STATE.all`),
  checks every revoke sum, re-fetches `refs/payloads/*` with
  one exclusion per revoked action, lists every payload ref
- runs even when the remote has nothing new (`goto RECV`
  skips the merge, not this pass)
- only these can change in one pull:
    - actions after the merge-base, on both sides (fast-
      forward: just the new commits)
    - targets of the votes (like, dislike, revoke, unrevoke)
      among them, however old
- before the merge-base, all was reconciled by earlier pulls

# Cause 2: `hardfork` on every winning remote (`sync.lua:47`)

- builds both full orders, walks back until an entry is
  `time.fork` (7 days) old
- runs when the remote wins, fast-forwards included
- a plain fast-forward (no merge commit in `loc..rem`)
  cannot reorder my order: my order is a prefix
- busy chains (chat): the last 7 days hold every action, so
  the walk covers the whole chain

# Fix 1: affected set only

- affected = cids in `merge-base..HEAD` (both sides) + the
  targets of their votes
- revoke checks and anchor updates only for the affected set
- fetch only the payload refs of the affected set
- nothing new (`goto RECV`): skip the pass
- `STATE.read` of the tip only; no `STATE.all`

# Fix 2: `hardfork` from the tips

- the order is in the snapshot: chunks of 200 cids
  (`order/<nnnn>.txt`), lazy, append-only; count and last
  are O(1) (`order_n`)
- today (`sync.lua:47`): `STATE.order(G)` and
  `STATE.order(G2)` without a chunk index load EVERY chunk,
  then the walk back reads `time.apply` per action
  (`STATE.fetch`, batches of 256) until one is 7 days old
- instead, compare from the tips:
    - walk both orders' chunk blob ids back from the tail
      until equal (usually the last 1-2 chunks differ)
    - in the first differing chunk: the first differing
      entry = the split point
    - read `time.apply` of that ONE entry: >= `time.fork`
      old -> hard fork, else ok
    - plain fast-forward: my chunks unchanged but the last,
      split past my tip -> never a hard fork, no reads
- cost: O(differing chunks) + one action read

# Review (26/10/07)

- fix 1 breaks payload healing
    - today the pass re-fetches and re-anchors ANY action
      missing its bytes, however old: a payload one peer lacked
      arrives later from another
    - affected set only: an old missing payload is never asked
      for again
    - "nothing new: skip": worse, the remote may hold the bytes
      with no new commits
    - fix: a local set of cids missing their bytes, always added
      to the affected set; skip only when both are empty
- fix 2: compare WRITTEN snapshots
    - at the check, the remote-wins state holds the local loser
      replayed in memory: its changed chunks have no blob ids
    - the snapshot at `rem` is written: the first index where
      order(rem) and order(HEAD) differ = the same split point
    - chunk walk on those two refs; the one time read is HEAD's
      entry at that index
- fix 1 overlaps `260903-128KB.md` (main) step 2
    - both fetch payloads by explicit cids, not
      `refs/payloads/*`; 128KB adds an oversized list next to
      the revoked exclusions
    - same pass, two branches: write it once, or port one way

# Expected

- fix 1: -0.6 to -0.7 s per pull (~55% at 2,372 actions),
  growing with the chain otherwise
- fix 2: -0.2 s per pull (~15%); hard-fork checks become
  ~free
- a pull ~ fetch + apply new actions ~ 0.3-0.4 s, flat

# Order

- [x] fix 2 (local to `hardfork` in `sync.lua`), on the `rem`
  and HEAD snapshots (26/10/07, 45/45 suites pass)
    - `ls-tree` of both refs' `order/`; first differing chunk id;
      one `cat-file` per side; one `time.apply` read at the split
    - fallback (rem's order a strict prefix of mine): the old
      full compare against the new order; no test reaches it
    - `STATE.ORDER_K` exported
    - [x] measured (26/10/07, sims): `hardfork` + `update-ref
      HEAD` 0.18-0.20 s -> 0.03-0.04 s (see Evidence)
- [x] fix 1 (affected set from `merge-base..HEAD` + vote
  targets + missing-bytes set) (26/10/07, 45/45 suites pass)
    - set: remote side's actions + vote targets, my side's vote
      targets, `payloads-missing` (repo dir), all begs
    - no `STATE.all`, no `refs/payloads/*`, no negative refspecs:
      one fetch with a glob per cid (`refs/payloads/<cid>*`), a
      ref the remote lacks is no error (checked on git 2.43)
    - a fetched ref is kept only if its target == the action's
      blob (the fake-ref gap of 260903-128KB)
    - no `payloads-missing` yet (older repo): one full pass
      builds it
    - small chains: +2-9% on sync, cli-send, consensus,
      repl-remote-begs (fixed cost: merge-base, rev-lists, one
      `ACTION.read` per new commit, two `for-each-ref`)
    - untested: healing from a second peer, fake ref deletion
    - [ ] measure in the sims (expected: steps 9-12, 0.40-0.43 s,
      down to ~0.05 s)

# Process floor (26/10/07-08, one commit per fix, measured)

- harness: scratch `bench.sh`, 40-post chain, `strace -f -e execve`
  counts (lua + sh + git + ssh-keygen) per command; wall times
  noisy (sims running, load avg ~6)
- post 71 -> 26 procs (0.117 -> 0.056 s); like 71 -> 30;
  reps 13 -> 9; recv of 3 posts 224 -> 69; clone of 52 commits
  689 -> 467
- git.lua: commit object memo (`GIT.cat`, `cats`), empty tree
  constant, `GIT.refs` (one `update-ref --stdin`)
- ssh.lua: base64 in Lua (no base64|xxd|tr pipelines), private
  key parsed in Lua, verify with one `ssh-keygen -Y verify`
- init: `rev-parse refs/genesis HEAD` once, HEAD/GENESIS globals
- state.lua: one ls-tree per write; `load` (actions + members in
  one batch); pending window in the eager batch; `has` memo and
  `has_all`; `prelist` (a run's shards once); `absent`; snapshot
  ref deferred into the caller's batch
- rules/action: `RULES.needs` folds the advance window into the
  apply batch; the claimed signer names the member before verify
- sync recv: known tips (HEAD, FETCH_HEAD file), one merge-base,
  fast-forward skips hardfork/voided/replay when no sync merge is
  among the new commits, the final state kept in memory for the
  payload pass, payload checks via `cat-file --batch-check`, one
  ref batch; `maintenance.auto false` at init
- round 2 (26/10/08): post 26 -> 13 procs (0.056 -> 0.041 s);
  like 30 -> 19; recv of 3 posts 69 -> 49; clone of 52 commits
  467 -> 219
    - loose objects written from Lua (STATE.put: zlib stored
      blocks, Lua SHA-1 measured 9 MB/s, cheaper than a process):
      no hash-object, no mktree, payloads too; the 256 object dirs
      and the empty tree at init
    - commits minted in Lua, signed by one `ssh-keygen -Y sign`
      (git's own verify-commit accepts them)
    - refs: HEAD/genesis/begs read from their loose files; updates
      written as loose files (deletes still via update-ref)
    - meta `cid` + `tips`: a child's backs need no commit read
    - a run: prelist of its shards, `absent` marks, the floor in
      the prefetch, top/shard tree ids derived from listings
- round 3 (26/10/08): recv of 3 posts 49 -> 39 procs; `list order`
  7 -> 5 (no action loads: `revoked.txt` in the snapshot)
    - recv: no snapshot check for new commits (`has_set`), the
      new-commit listing decides nothing-new / fast-forward / the
      genesis check (merge-base only on a fork), the payload pass
      in one batch-check (anchors + blobs) with FETCH_HEAD for what
      the fetch brought, anchor moves in one ref batch
- floor reached with this layout: post = ls-tree + cat-file (read),
  cat-file (apply batch), ls-tree (the new cid's shard), ssh-keygen
  sign + verify; recv = 2 fetches (git's own 5 processes each) +
  ~8 calls + one ssh-keygen per new commit
- next (design): the read's listing + batch as one call needs a hot
  blob holding the window and tail (bytes duplicated per post);
  the payload fetch merged into the main fetch needs the sender to
  advertise payload refs by commit
- won't do: skipping the writer's own signature check (a design
  shortcut, not an optimization)

# Won't do

- parallel pulls into one peer (see `261005-races.md`)
