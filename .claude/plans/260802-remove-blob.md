# Remove Blob: Payloads Outside the DAG

Phase 2 of revocation.
Companion to `done/260721-revoke.md` (Phase 1 = display hide).

Fresh design, supersedes `260721-remove-blob.md`.
That plan kept payloads inside the commit tree and paid for it
everywhere; this one takes them out.

# Invariant

- every byte a USER authors lives in a payload blob OUTSIDE the
  commit DAG
- the DAG carries only protocol metadata (state, votes, pointers)
- therefore any user byte is removable with no effect on git

Everything below follows from this one rule.

# Non-goal: guaranteed network-wide forgetting

- signed + replicated: a holder cannot be compelled to delete
- one non-cooperative peer re-serves -> content is back
- what IS achievable:
    - honest peers drop the bytes and stop serving them
    - a new peer talking only to honest peers never gets them
- `reps.md:250` "not retransmitted" and README "right to be
  forgotten" are cooperative, not enforced

# Layout

```
commit (signed)
  tree/  post-<t>-<r>.txt   -> pointer blob = "<payload-sha>"   IN DAG
         .freechains/...    -> state, votes                     IN DAG
  msg    "-" + trailer "Freechains: post"                       IN DAG

refs/payloads/<payload-sha> -> payload blob                     OUT
```

- the pointer is signed (it is in the signed tree)
- the ref name IS the object id -> self-verifying, no trust step
- the payload is reachable ONLY from its own ref

# Why out of the tree

- a blob in a tree is part of the commit closure
- so removing it breaks clone, push, checkout, merge, commit
- the old plan absorbed that with:

| symptom | machinery it forced |
|-----------------------------|------------------------------|
| removed blob breaks serving | `filter=blob:none` |
| filter sets a promisor      | strip it, 2 spellings |
| filter omits ALL blobs      | by-hash batch + fallback |
| batch is atomic             | hard-fail rules, 2 revoke sets |
| state file is a blob too    | pull `state/posts.lua` alone |
| `commit` -> `write-tree`    | 6 sites -> `commit-tree` |
| worktree/index hold path    | `skip-worktree`, `merge-tree` |
| `push` reads every object   | genesis into `refs/begs/` |

- out of the tree, all of it disappears
- vanilla clone / fetch / push / commit keep working, before and
  after removal

# Payload refs

- write: `git hash-object -w` then
  `git update-ref refs/payloads/<sha> <sha>`
- keep-alive: the ref (gc keeps it, `fsck` clean)
- remove: `git update-ref -d` then `git gc --prune=now`
- verify: drop any ref whose name is not its own object id
- default clone does NOT carry them (not in the default refspec)

# Sync

One fetch, no filter, no promisor, no fallback:

```
git fetch <peer>
    refs/heads/main:...
    refs/begs/*:...
    refs/payloads/*:refs/payloads/*
    ^refs/payloads/<locally-revoked-sha>   (one per revoked)
```

- the negative refspec is what keeps removed bytes from coming
  back on every sync
- nothing can be "missing": the peer serves what it advertises
- so no batch atomicity, no per-blob retry, no hard-fail rule
- targeted fetches send protocol-v2 `ref-prefix`, so O(n) payload
  refs are not advertised unless a wildcard asks for them

# Removal

- trigger stays decoupled from Phase-1 display hide
- act ONCE, on the final sums after a sync's full replay, never
  mid-walk (a sum can dip negative from ordering alone)
- author channel is final immediately (only a fresh signed
  unrevoke lifts it, `reps.md:294`)
- a post that recomputes non-negative needs no restore step: it
  is simply back in the set the next sync's refspec asks for

# Gated unrevoke

- `unrevoke`, and a `like` that would actually flip `is_revoked`
  from true to false, must materialize the payload FIRST
- local object store, else fetch `refs/payloads/<sha>` from a peer
- refuse otherwise:
    - `ERROR : chain unrevoke : blob unavailable`
- guarantees at least one holder the moment a post leaves REVOKED
- a self-like that cannot lift an author revoke is NOT gated

# Read path

- `get.lua --payload`: read pointer from the tree, then
  `git cat-file blob <sha>`
- revoked -> `ERROR : chain get : revoked post`
- absent but not revoked -> `ERROR : chain get : payload
  unavailable`
- never a raw Lua traceback

# No user bytes in the DAG

- `--why` moves out of the commit message into a payload blob
    - same ref, same removal path as a post payload
    - no special case for like/dislike
- commit message is always `-`
    - trailers stay: `Freechains: post|like|state`
- `get.lua --metadata` reads `why` as a payload, not from `%B`
- consequence: abusive text is always removable, wherever it was
  written

# Rejected

- git notes as the payload store (`--ref=payloads`)
    - MEASURED: fetching a peer's notes ref re-imports bytes this
      node deleted, even when the ref update is REJECTED
    - notes diverge -> non-fast-forward -> a merge per sync
    - `merge -s union` keeps the local deletion, so removals do
      not propagate either -> syncing them buys nothing
    - unsigned mutable channel consensus never validates
    - integrity still needs a signed pointer -> notes add nothing
    - local-only notes reduce to a keep-alive anchor, and then
      force by-hash fetch (atomic batches) instead of refspecs
- filtered transport (old plan) -> table above
- tree rewrite / `--orphan` -> new hashes, DAG broken
- `git replace` -> packer ignores it, serving still fails
- sidecar outside git -> loses dedup, integrity, transport

# Evidence

Measured in scratch repos, git 2.43:

| test | result |
|--------------------------------------|-------------------|
| blob only ref-reachable survives gc  | OK |
| vanilla clone carries no payloads    | OK |
| selective fetch of chosen refs       | OK, one pack |
| wildcard + `^ref` excludes revoked   | OK, one round trip |
| after `update-ref -d` + gc: fsck     | clean |
| then full clone / push / checkout    | all OK |
| notes: rejected fetch still imports  | bytes came back |
| notes: divergence                    | non-fast-forward |
| explicit refspec fetch               | sends `ref-prefix` |

# Code impact

| file | change |
|------------------|-----------------------------------------|
| `post.lua`       | payload -> `hash-object -w` + ref; write pointer file; msg `-` |
| `like.lua`       | `--why` -> payload blob + ref; msg `-` |
| `get.lua`        | deref pointer; two error cases |
| `sync.lua`       | one fetch, payload refspecs + negatives |
| `chain/common.lua` | payload helpers, revoked refspecs |
| `chains.lua`     | nothing (no filter, no promisor, no gc config) |

Untouched: signing, consensus, state files, `commit`, `merge`,
`checkout`, `reset`.

# Open questions

- can a like's `--why` be revoked, and by whose vote
    - overlaps `done/260730-revoke-like.md`
- identical payloads share one ref -> shared fate on removal
- orphan payload refs after `post --beg` + `reset --hard HEAD~2`
- pointer file naming: keep `post-<t>-<r>.txt` so
  `commit_file()` and filename metadata survive
- back-compat: none, chains predating this get recreated

# Progress

- [ ] payload write/read/remove helpers in `chain/common.lua`
- [ ] `post.lua`: payload ref + pointer file
- [ ] `like.lua`: `--why` as payload
- [ ] messages always `-`, drop `%B` parsing in `get.lua`
- [ ] `get.lua`: pointer deref + two error cases
- [ ] `sync.lua`: payload refspecs + negative refspecs
- [ ] removal at end of sync replay
- [ ] gated unrevoke / lifting like
- [ ] README: revocation is cooperative, not enforced

# Cross-references

- `260721-remove-blob.md` — superseded, keeps the measurements
- `done/260721-revoke.md` — Phase 1, display-level hide
- `reps.md:243,250,287-312` — revoke rule and channels
- `prune.md` — `--orphan` flatten, rejected here
- `git.md`, `layout.md`, `metadata.md` — payload leaves the tree
