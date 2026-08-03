# Problem

- `commit()` validates a `state` commit only via `now` (PEAKS)
- `authors/posts/order` never compared: forgery is well-formed
- full compare exists only at FF tip (`write` + `git diff`)
- forged values ignored as record, alive as anchor:
    - `G_oct` loaded from commit tree with no validation
    - forged reps feed replay and `consensus()` (merge control)
- three escapes: diverge tip, interior, merge side (beg branch)

# Approach

- verify every `state` commit inside `commit()` (sync.lua)
    - one funnel: FF interior, diverge interior, merge sides
    - `climb`/`meet` already visit every commit, sides included
- context-free: check against the commit's OWN parent
    - no replay baseline needed; works on any merge side
- keep `now` check (PEAKS) as is

# Shapes of state commits

- 1 parent: seals exactly one post/like/revoke
    - `post.lua`: parent is the post
    - `like.lua`: parent is the vote
        - vote may be 2-parent `-X ours` merge (like-on-beg)
- 2 parents: sync-merge state (`sync.lua` diverge path)
    - content = full merge replay (winner + loser)

# Verification rules

- 1 parent `P`:
    - `trailer(P)` must be post/like/revoke, else invalid
    - `G2` = 4 state files from P's own tree
        - `-X ours` makes a like-merge tree = pre-vote state
    - like-on-beg: pre-apply beg side first
        - `commit(G2, P^2~1, beg=true)`
    - re-apply P by recursing into `commit(G2, P, beg)`
    - beg inference for signed post: `reps <= 0` in G2
        - mirrors `apply` validation exactly
- 2 parents:
    - `G2 = G`: `meet()` has just re-derived both sides
    - same equality FF `write`+`diff` already banks on
- compare: `serial(G2[f])` vs `git show hash:state/f.lua`
    - files: `authors`, `posts` only
    - skip `order`: honest peers may disagree (separate bug,
      see `bug-climb-ancestor`)
    - skip `now`: PEAKS check is stronger

# Prerequisite: date pinning

- replay reads `%at`, writer records `CMD.now`
- without `--now` they can skew by 1s: false mismatch
- always set `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` from `CMD.now`
    - in `freechains.lua` (move `CMD.git` out of `if ARGS.now`)

# Steps

- freechains.lua: pin commit dates unconditionally
- sync.lua `commit()`: add state verification branch
    - helpers: `tree_raw`, `tree_state` (local to sync.lua)
    - reject invalid parent shapes
- keep FF tip check as end-to-end probe

# Won't do

- `chains add --clone` validation (separate plan)
- removing FF `write`+`diff` check
- `order` comparison (blocked on order-consensus bug)
- double sig/mode check in recursion (~2x replay, accepted)
