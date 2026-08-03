# Problem

- `commit()` validates a `state` commit only via `now` (PEAKS)
- `authors/posts/order` never compared: forgery is well-formed
- full compare exists only at FF tip (`write` + `git diff`)
- forged values ignored as record, alive as anchor:
    - `G_oct` loaded from commit tree with no validation
    - forged reps feed replay and `consensus()` (merge control)
- three escapes: diverge tip, interior, merge side (beg branch)

# Status

- fix DEFERRED: folds into redesign step S9 (see below)
- sections Approach..Steps kept as spec for the check itself
- landed: S1-S5 (see step list); next: S6, then S8

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

# Clash with redesign (260802-redesign.md)

- redesign makes the FIX easier, the TEST obsolete as written
- fix easier: verification collapses to one uniform rule
    - join: every commit carries state -> one compare, no
      3-shape dispatch
    - action self-describes (`actions/<id>.lua`) -> no trailer
      trust, no metadata probing, no like-on-beg splice
    - standalone state commit dies by shape:
      1 parent + no action file = invalid (redesign par.5)
        - kills test scenarios 1 (tip) and 2 (interior) for free
    - beg becomes ONE commit -> scenario 3 covered by same rule
    - merges compare vs replay `G` (same as 2-parent rule here)
- not free: forgery migrates INTO an action commit's `state/`
    - recompute-and-compare still required
    - redesign par.9: "should land with this, not after"
- test cannot survive redesign mechanically:
    - asserts trailer "state" -> trailers deleted
    - forges standalone state commit -> shape gone
    - beg anatomy `ref~1` / amend trick -> beg is 1 commit
    - `.freechains/state/` paths -> layout renamed
- durable parts of THIS plan under redesign:
    - date pinning, `serial` byte-compare, skip `order`,
      merge = replay-compare
- throwaway parts: shape dispatch, beg inference, beg splice

# Redesign: independent steps, tests green after each

- substrate, no dependencies, any order:
    - S1: pin `GIT_*_DATE` from `CMD.now` unconditionally
        - DONE (freechains.lua); test: `tst/bug-now-skew.lua`
    - S2: `sign` from `.pub` file BEFORE commit (not `ssh.pubkey`)
        - DONE: `ssh.pub()` + post.lua + like.lua
        - bad key now fails EARLY, same error message
    - S3: `apply` takes `T.parents`, not `T.hash`
        - DONE: `PEAKS(T.parents)`; 4 call sites pass
          `parents(hash)`; `T.hash` stays as state key until S8
    - S4: explicit `refs/begs/*` refspec on `--clone` (latent bug)
        - DONE: fetch after clone in chains.lua
        - test: repl-local-begs, manual fetch removed
    - S5: `tmp/` -> `.git/`; delete `.gitignore`
        - DONE: `.git/allowed_signers`; skel loses `tmp/`,
          `.gitignore`, `.gitkeep`; tests repointed
    - S6: `.freechains/state/` -> `state/`; `genesis.lua`,
      `random` to root; update mode check, skel, test paths
        - consolidate authors/posts/order -> `state.lua`
        - `now.lua` stays apart (PEAK hot path; full merge is
          an open question in redesign par.11)
- coupled cluster, strict order, each still green:
    - S8: mint ID (`hash-object` of action file); key
      `posts`/`order` by ID; commit<->ID index; print IDs
        - needs S2 + S3; flatten `likes/`/`revokes/` here
        - bulk: tests hashes -> IDs
    - S9: join commits: apply-before-commit, drop rollbacks,
      `beg~2` -> `beg~1`, destroy fixes (needs S8)
        - S7 lands HERE: uniform per-commit state compare
        - done when rewritten `bug-forged-state` passes
    - S10: payload eviction: `refs/payloads/<id>`, refspecs,
      clone, `--why` off post (needs S8)
    - S11: delete trailers; structural classification (needs S9)
    - S12: shrink `posts.lua` to `{maturity, reps, revoke}`
      (needs S8)
    - S13: revoke deletes payload ref; `gc` policy (needs S10)
- decision: S7 folded into S9 (settled)
    - no deployment; attacker theoretical
    - `bug-forged-state` not in default suite: red marker only
    - avoids throwaway shape dispatch / beg splice / inference
    - redesign par.9: comparison lands WITH the join
- branches:
    - `main`: fixes + design-neutral cleanups (S1, S4, S5)
    - `260803-redesign`: substrate + cluster (S2, S3, S6, S8+)
    - criterion: useful even without the redesign -> `main`
- progress: S1-S5 done; next S6, then S8
