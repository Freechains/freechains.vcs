# Redesign: Lua Database as the Action Layer

Five changes that compose into one:

1. **Join** the action and state commits into a single commit
2. **Flatten** `.freechains/likes/`, `.freechains/revokes/` into
   `actions/<id>.lua` — one file per action, kind-agnostic, and
   no longer hidden
3. **Self-describe** each action with `action` and `backs`, where
   `backs` holds *action IDs*, not commit hashes
4. **Evict payloads** from the tree into ref-anchored loose blobs
5. **Evict state** from the tree into per-commit local snapshots
   (`.git/states/<cid>.lua`, S15) — commit what peers must agree
   on; cache what any peer rederives alone

The result is a division of labour:

| Layer | Owns |
|---|---|
| **git** | transport, signatures, object integrity, merge topology, consensus |
| **Lua DB** | action identity, the action DAG, derived state |

Reads (`list`, `get`, `reps`, `--dag`) stop touching git entirely.
Consensus (`octopus`, `merge-base`, `rev-list`) stays in git,
because it is a transport question.

## 1. Why the commits are joined today

State is keyed by the action's own commit hash:

```lua
G.posts[T.hash] = { ... }          -- common.lua
G.order[#G.order+1] = hash         -- post.lua, like.lua
T.sign = ssh.pubkey(REPO, hash)    -- needs the commit to exist
```

A commit cannot contain its own hash, so the state describing an
action cannot live in that action's commit. The second commit
exists only to close that gap. An ID minted before the commit
removes the cycle and the order inverts:

```
write payload blob      -> git hash-object -w
anchor it                  refs/payloads/tmp-<rand>   (§3)
build action file          (backs, action, sign, time, blob)
id = blob hash of that file
apply(G, ...)              -- may fail: nothing committed yet
write actions/<id>.lua + state/
git add; git commit -S
rename ref              -> refs/payloads/<id>
```

`apply` now runs before the commit, so failure just returns — the
`reset --hard HEAD~1` rollbacks in post.lua:70-74 and
like.lua:101-106 disappear, and `--beg`'s `HEAD~2` becomes
`HEAD~1`.

## 2. The action file

```lua
-- actions/<id>.lua
return {
    action = 'post',                    -- 'post'|'like'|'revoke'
    backs  = { '<id1>', '<id2>' },      -- action IDs, not commits
    sign   = 'ssh-ed25519 AAAA...',     -- or nil (unsigned beg)
    time   = 1785000000,
    blob   = '<git blob hash>',         -- payload, see §3
    -- like / revoke only:
    post   = '<id>',                    -- or author = 'ssh-...'
    n      = 1000,
}
```

Everything an action *is* lives here. `sign` and `time` are
duplicated from the commit deliberately — that is what lets the
DB answer without a git call — and both are validated against the
commit on receipt (§6).

## 3. Payloads live outside the tree

The payload is written as a loose blob and anchored by a ref:

```
refs/payloads/<id>  ->  <payload blob>
```

Never added to the tree. Its hash is recorded in the action
file's `blob` field, which is what binds it: the ID is the action
file's hash, so the ID transitively commits to the payload's
content without the payload ever entering a commit.

One payload per action, meaning set by kind:

| Action | Payload | Required |
|---|---|---|
| `post` | the post content | yes |
| `like` / `revoke` | the `--why` text | no |

`--why` therefore disappears from `post` — a post's payload *is*
its content, and a second free-text field would be redundant.

### Why this makes revocation real

Today revocation is advisory: `is_revoked` makes `get --payload`
refuse (get.lua:33-35), but the blob stays in every subsequent
tree forever and no amount of history rewriting removes it
without breaking every hash downstream.

With payloads out of the tree, deleting `refs/payloads/<id>`
makes the blob unreachable and `git gc` collects it. Commits,
trees, action files, IDs and the DAG are all untouched — only the
bytes vanish. Replay still works, because validation never needs
the payload present.

This is right-to-be-forgotten in the cooperative sense: a peer
that chooses to keep the blob can. That is inherent to p2p and
worth stating plainly rather than implying otherwise.

### Key the ref by action ID, not blob hash

`refs/payloads/<blob-hash>` is broken by shared content. Alice
and Bob post the same image: one blob, one ref. Alice revokes,
the ref goes, and **Bob's post loses its content**.

Keying by action ID gives refcounting for free. A ref's *name*
and *value* are independent: the ref is named by action ID and
points at the blob sha, and reachability follows the value. Git's
GC is reachability-based, not refcount-based, so sharing needs no
bookkeeping at all.

Verified:

```
two refs -> one blob;  gc --prune=now  -> blob survives
delete one ref;        gc --prune=now  -> blob survives
delete the last ref;   gc --prune=now  -> blob gone
```

Revocation is therefore exactly "delete my own ref", with correct
semantics for shared content and nothing to maintain.

### The write -> anchor window

`hash-object -w` writes an unreferenced blob, and the ID is not
known until the action file is built, so there is a gap before
`update-ref`. Git's default two-week `gc.pruneExpire` covers it,
but the revocation policy below wants `--prune=now`, and a
concurrent gc would reap it.

Anchor immediately under a temporary ref, rename once the ID is
known, and delete it if `apply` fails.

### Transport becomes selective

`sync` must add `refs/payloads/*` to both refspecs
(sync.lua:15, :27-28) — but because the action file pins the
payload hash, the DAG, reputation and consensus all validate with
**no payloads present at all**. A peer can sync structure cheaply
and fetch content on demand, and a revoked post simply never
arrives.

Push of a blob ref works as-is
(`* [new reference] refs/payloads/act1`). Three interactions to
get right:

- **Clone silently drops them — then destroys them.** A default
  clone fetches no `refs/payloads/*`. Worse, on a *local* clone
  the blobs arrive anyway via pack copying, so the chain looks
  intact until the first `gc --prune=now` reaps every payload at
  once:

  ```
  after default clone:   blob, refs=[0]
  after gc --prune=now:  could not get object info
  ```

  `chains add --clone` (chains.lua:159) must pass an explicit
  refspec. The same latent bug already exists for `refs/begs/*`.
- **Fetch resurrects deletions.** Pulling `refs/payloads/*`
  re-anchors blobs that were deliberately dropped. Needs a
  post-fetch pass deleting payload refs for revoked actions —
  same shape as the stale-beg cleanup at sync.lua:586-601.
- **Beg cleanup must not touch payloads.** sync.lua:586-601
  deletes `refs/begs/*`; `refs/payloads/*` for the same action
  must survive.

### Commit messages go empty

With `--why` gone from posts and moved to a payload blob for
likes, no user-written text remains for the message. That is
forced, not incidental: a commit message lives inside the commit
object, so anything there is undeletable and would defeat the
point. Keep the existing `(empty message)` placeholder — it is
not user content, so it raises no deletion question.

Cost: `git log --oneline` stops being informative. Accepted as
the price of making all user text deletable.

## 4. The ID is the action file's git blob hash

```
id = git hash-object actions/<id>.lua
```

Nothing else. `sign`, `time`, `action`, `backs` and `blob` all
live inside the file, so the file's own hash already covers them.

| Property | Why it holds |
|---|---|
| Known pre-commit | `git hash-object` on the content |
| No cycle | content -> hash -> filename; only the *name* depends on the ID |
| Verifiable | git computes and checks blob hashes inherently |
| Kind-distinct | `action` is inside the hashed content |
| Author-distinct | `sign` is inside the hashed content |
| Survives revocation | depends on the payload's *hash*, not its presence |

The author field is what makes this safe. Without it the ID would
collide *by construction*, and likes are the common case, not an
edge case: two authors liking the same post by the same amount
from the same heads produce byte-identical files. With `sign` and
`time` folded in, the residual collision is one identity acting
identically from two machines in the same second — which is the
same action, so deduping it is correct.

Deliberately **not** an input: the commit's parents. Including
them would make an action's identity depend on merge plumbing —
the exact coupling this redesign removes. `backs` pins the DAG
position instead, and it is validated (§6).

Bonus: `git cat-file blob <id>` retrieves any action directly,
with no filename lookup and no tree walk.

> **Note on SHA-1.** This makes the ID a git blob hash, so ID
> forgery reduces to a git object collision. That is the same
> assumption the whole chain already rests on, not a new one, and
> git enables SHA-1DC by default. If it matters, the answer is
> `git init --object-format=sha256` at `chains add`, not a
> bespoke hash.

## 5. Commit shapes — and no trailers

### The tree determines everything

An action commit adds exactly one `actions/<hex>.lua`. With
payloads evicted, that is the *only* added path, and every path
in the tree is freechains-controlled — no user-chosen filenames
anywhere. So the commit <-> ID map needs no declaration:

```
added path under actions/ matching <hex>.lua
  -> its blob sha
  -> the id
```

It is *doubly* determined: the filename's hex must equal the
blob's sha, because the ID **is** the blob hash.

Classification is structural and total:

| Commit | Adds action file | Parents |
|---|---|---|
| action | exactly one | 1, or 2 for a beg-merge like |
| merge | none | >= 2 |
| genesis | none | 0 |
| **invalid** | none | 1 |

The last row matters: it rejects a linear no-op commit that would
otherwise pass as a merge.

One subtlety: this needs `--cc` semantics — absent from every
parent. First-parent diffing would misclassify a merge, whose
incoming action file *is* new relative to parent 1. get.lua:24
already carries an `assert(not files:match("\n%S"))` guarding
exactly this behaviour, so it is load-bearing subtlety rather
than new risk.

### Merges get no action file

They need none: `backs` carries the action-level topology
precisely *by* skipping merges, and the structural rule above
identifies them. Giving them `action = 'merge'` entries would
push transport artifacts into the action database — backwards —
and they would need IDs, which would land them in `order.lua` and
change consensus semantics.

### Which is why there is no trailer

A trailer can only ever *confirm* what the tree already says. It
cannot add security — an attacker who declares `merge` while
adding an action file is caught by the tree, not by the
declaration — so its entire contribution is one more field that
can disagree, and one more check to keep them from disagreeing.

Everything currently reading one resolves without it:

| Site | Replacement |
|---|---|
| `common.lua:37` (`backs()`) | deleted — `db[id].backs` |
| `sync.lua:225` (kind check) | tree derivation |
| `sync.lua:408` (`is_beg_merge`) | `db[id].action == 'like'` |
| `sync.lua:503`, `:553` (skip `state`) | state commits are gone |
| `get.lua:13` | `db[id].action` |

So `trailer()` (common.lua:5-11) is deleted and all seven
`--trailer` flags come off the commit invocations — four are
`Freechains: state`, which vanishes with the state commits
anyway. The commit envelope ends up carrying **zero** freechains
semantics: tree, parents, signature. Also gone: get.lua:54
strips the trailer back out of the message to compute `why`.

### Cost: the index needs diffs

The bridge between the layers is a commit <-> ID index, built in
one pass:

```
git log --cc --name-only --diff-filter=A --format='C %H' <range>
```

`--cc` is required: git shows no diff for merge commits by
default, which would silently drop beg-merge likes — the one
merge that *is* an action.

Heavier than the format-only pass a trailer would allow, but the
same order as `git log --stat`, once, and incremental after that
(`old..new` following a sync).

**Sequencing:** build the index over the fetched range *before*
replay. `climb`/`meet` need `is_beg_merge` per commit
(sync.lua:408), and that must be an index lookup, not a tree diff
per node.

## 6. The two-DAG problem

This is the main risk and the thing to get right.

`backs` asserts an ancestry. Git's commit parents assert another.
Consensus (`consensus()`, `octopus()`, `hardfork()`) runs on
git's. If the two disagree, the chain has two contradictory
histories and navigation silently diverges from consensus.

So `backs` cannot be trusted as received. On every incoming
action, `commit()` in sync.lua must recompute the true action
ancestors from git — parents, recursing through `merge` commits,
which is `backs()` in common.lua:32-52 minus the `state` case —
and reject on mismatch.

That makes `backs` a **validated cache**, not a claim:

> The Lua DB is authoritative for navigation *after* it has been
> reconciled against git once, at receive time.

Reads are the common case, so this still buys nearly everything:
after validation, `list`, `get`, `reps` and `--dag` make zero git
calls. What it does not buy is a receive path free of git
traversal — and it should not, because that traversal is the only
thing keeping the two DAGs honest.

Three more checks belong in the same place, all cheap:

- `id` equals the blob hash of the file it names (`git ls-tree`)
- file's `sign` equals the commit's signature pubkey — otherwise
  an attacker can replay Alice's action file under their own
  signature
- file's `time` equals the commit's `%at`

And one that must **not** be required: the payload's presence.
Validating an action against a missing blob has to succeed, or a
single revocation breaks replay for everyone. Check
`hash-object == blob` only when the payload is actually there.

## 7. What the DB replaces

| Today | After |
|---|---|
| `backs(hash)` recursion (common.lua:32) | `db[id].backs` |
| `trailer(hash)` per commit (common.lua:5) | `db[id].action`; function deleted |
| `ssh.pubkey` per commit (cat-file + base64 + xxd) | `db[id].sign` |
| `log -1 --format=%at` in get.lua, hardfork | `db[id].time` |
| `merge-base --is-ancestor` membership (get.lua:5-12) | `db[id] ~= nil` |
| `diff-tree --cc` `commit_file()` (get.lua:20-27) | `db[id].blob` |

`commit_file()` is the best deletion here — it infers the payload
by asking for the one path this commit added and `assert`s there
is exactly one. The action file names the blob outright.

### The piece that must also move

`PEAKS(parents(h))` drives the time-monotonicity check in
`apply`, and `PEAK` reads `state/now.lua` out of a commit tree
(common.lua:96-128). That is a git call in the *write* path, so
the goal is not met until it moves too: store the per-action peak
in the DB and fold over `backs` instead of over commit parents.
Same formula, same verification, no `git show`.

## 8. Layout: `actions/` + `state/`

> **Superseded in part by S15**: `state.lua` leaves the tree for
> `.git/states/<cid>.lua`; `.gitattributes` dies with it. The
> tree keeps only `actions/`, `genesis.lua`, `random`. The
> in-tree consolidation below landed as S6b and remains the
> shape S15 starts from.

`.freechains/` existed to keep internal files out of the user's
way. With payloads evicted (§3) there are no user files left, so
the prefix hides nothing from anyone. Drop it — but keep the
grouping, because the objection was the hiding, not the
structure:

```
actions/              <id>.lua, one per action (sharded below)
state.lua             authors, posts, order, now — one table
genesis.lua           chain definition
random                uniqueness seed
.gitattributes        state.lua merge=ours
```

Five entries, self-describing: `ls` now says what the repo is.

All four state facets consolidate into a single `state.lua`
table: one read everywhere (`G_oct`, `tree_state`, every `dofile`
site), atomic by construction, one path in the mode check, and
`write(G)`/load are symmetric. Transitional cost: `PEAK` reads
the whole file per commit while it still reads trees — accepted
as is, and gone entirely when the peak moves into the DB folded
over `backs` (§7).

The split is the same one the whole design rests on — `actions/`
immutable, `state/` derived and mutable — and it keeps the mode
check to two prefix assertions rather than an enumeration of root
paths mixed with hex-pattern matching:

```
added    -> must be actions/<hex>.lua, exactly one
modified -> must be under state/
```

Three things fall out:

- **`tmp/` leaves the worktree for `.git/`.** It is untracked
  scratch for `allowed_signers` (ssh.lua:66), and `.git/` is
  where per-repo scratch belongs.
- **`.gitignore` is deleted.** Its only content is
  `.freechains/tmp/*`, which goes with `tmp/`. Nothing else needs
  ignoring, and its absence is mildly useful — a stray file in
  the worktree now shows as untracked instead of being silently
  swallowed.
- **No `.gitkeep` anywhere.** The skel needs three today
  (`likes/`, `revokes/`, `tmp/`). `actions/` need not exist at
  genesis at all: git directories are implicit in paths, so it
  springs into being with the first action — and no non-hex file
  ever sits inside it for the mode check to whitelist.

### One caveat: sharding

Git stores a tree object *whole*. A directory of n entries that
gains one file produces a new n+1 entry tree — so m actions in
one flat directory cost O(m²) tree entries over the chain's life.
Packfile delta-compression absorbs much of this, but git shards
its own object store into 256 prefix buckets for exactly this
reason.

Recommend the same: `actions/ab/cdef....lua`. This is not the
per-kind structure being removed — it carries no semantics, it is
purely mechanical, and the DB never sees it. Keeping it under
`actions/` also keeps 256 two-hex directories out of the repo
root.

Worth noting the same shape already exists: `state/posts.lua` is
rewritten in full on every commit. Since `author` and `time`
become derivable from the action file, `posts.lua` can shrink to
the genuinely mutable fields — `{maturity, reps, revoke}` —
which cuts the constant.

## 9. Consequences

**Content conflicts become impossible.** Action files are
uniquely named by content hash and only ever added; identical
actions produce identical files; `state/` is `merge=ours`; no
user-named paths exist. Nothing can conflict, so
sync.lua:506-515's `"content conflict"` path and its
`merge --abort` can go.

**The mode check becomes exact.** Exactly one added
`actions/<hex>.lua`, `A|M` confined to `state/`, nothing else
permitted — replacing the two disjoint permission sets at
sync.lua:243-275. *(S15 tightens further: no `M` at all — a
commit adds one action file, or nothing and is a merge.)*

**Filename collisions disappear.** post.lua:16-22 and :30-37
error when a payload name is taken. With no payload in the tree
there is no name and no collision.

**Pruning becomes possible.** History flattening (prune.md,
`checkout --orphan`) discards commits, and with them everything
stored only there: signature, `%at`, trailer, parents. Today a
flattened chain would keep `state/` totals but lose every
action's author, time and DAG — unreplayable. With action files,
the orphan tree alone carries the whole logical history
(`sign`, `time`, `action`, `backs`, `blob` per action), so a
pruned chain remains complete and navigable. One limit: the
pruned prefix keeps the *record* but loses the *proof* — the
signatures go with the commits, so trust in it rests on peers
accepting the new root.

**Closes an existing hole.** Replay never compares its recomputed
state against what a commit carries. `commit()` (sync.lua:328-335)
checks only `PEAK`; the full comparison happens once, in the
fast-forward path (sync.lua:443-452), and never in the diverge
path. So a commit carrying forged `authors.lua` passes the mode
check and is merely passed through — and `G_oct` is then loaded
straight from a commit tree (sync.lua:363-374). Joining makes
every commit a state commit, so the comparison becomes uniform
and cheap. It should land with this, not after.
*(Superseded by S15: state is no longer transmitted, so the hole
dies by removal — there is nothing to compare.)*

**`destroy` needs three fixes.** chain/destroy.lua (the hard-fork
escape hatch) is the one command whose correctness depends on
commit *arithmetic*, so the join breaks it:

- `beg~2` (destroy.lua:81) assumes "a beg is two commits (post +
  state)". Joined, a beg is **one** commit, so it becomes
  `beg~1`. The ref also renames to `refs/begs/beg-<id>`.
- `trailer()` at destroy.lua:38 and :59 goes with the rest (§5) —
  the kind check and the `~= 'state'` output filter both become
  DB lookups, and the output prints IDs.
- Destroying an action must also delete its
  `refs/payloads/<id>`, or orphaned refs keep anchoring blobs for
  actions that no longer exist. Same shape as the stale-beg
  cleanup destroy.lua already does at :72-89.

Its parent-walk (`hash^1`, destroy.lua:47-49) survives untouched
and actually gets simpler: every commit carries state now, so
"land on the parent" is unconditionally a valid tip rather than
relying on it being a state commit, a merge, or genesis.

Worth noting destroy.lua:6-7 states the dependency outright —
*"Chain state lives in-tree, so the reset restores it along with
the commits: nothing else to rebuild"*. That is independent
support for keeping state committed rather than moving it to a
local cache. *(Reversed by S15: the reset restores commits only;
state comes from `.git/states/<tip>.lua`.)*

**The signing key must be read before committing.**
`ssh.pubkey` parses a signature out of an existing commit, so it
cannot supply `sign` any more. `--sign` is a private key path
(`--sign="$KEYS/alice"`) and the canonical pubkey form is the
first two fields of the `.pub` file (guide.sh:115). There is no
commit-then-`--amend` workaround: `sign` is inside the file, the
file's hash is the ID, and the ID names the file.

**`apply` takes parents, not a hash.** It calls
`PEAKS(parents(T.hash))`, but at write time the commit does not
exist. The parents are `HEAD` (plus `MERGE_HEAD` for a beg
merge), always known to the caller.

**The working tree empties.** No user files remain — the repo
becomes purely a database, `git status` is always clean, and
posts are readable only through `chain get --payload`. Consistent
with "git is transport", but it does close the door on browsing a
chain with vanilla git (git-social.md).

**Surface changes.** `post` prints an ID; `like`/`get`/`reps`
take IDs; `refs/begs/beg-<id>`; `order.lua` holds IDs; `post`
loses `--why`. Every test asserting on commit hashes needs
updating — the bulk of the mechanical work.

## 10. Steps

Fine-grained ladder (replaces the original coarse list); tests
green after each step. Progress is tracked here.

- substrate, no dependencies, any order:
    - S1: pin `GIT_*_DATE` from `CMD.now` unconditionally
        - DONE (freechains.lua); test: `tst/bug-now-skew.lua`
    - S2: `sign` from `.pub` file BEFORE commit (not `ssh.pubkey`)
        - DONE: `ssh.pub.key` + post.lua + like.lua
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
    - S6b: FULL merge: authors/posts/order/now ->
      `.freechains/state.lua` (one file, one table, in prefix)
        - DONE: READ/WRITE, PEAK, mode check, all loads, skel,
          `.gitattributes`, test literals; state.lua generated
          at init (pioneers + now)
        - PEAK reads whole file per call: accepted (small
          chains); dies at par.7 (peak folds over `backs` in DB)
- coupled cluster, strict order, each still green:
    - S8: mint ID (`hash-object` of action file); key
      `posts`/`order` by ID; print IDs
        - S8.1 DONE: `ACTION`/`BACKS`/`COMMIT_ACTION`
          (common.lua); post/like write
          `.freechains/actions/<id>.lua` in the action commit;
          get.lua excludes it
            - flat, unsharded (empty-dir vs `diff -r`);
              shard at S6a
        - S8.2a DONE: `G.posts` keyed by action ID
            - `apply` takes `T.id`; `T.post` is an ID
        - S8.3 DONE: `G.order` holds action IDs
            - id -> commit only at git boundaries: `ORD` map,
              `ACTION_COMMIT` fallback (hardfork window,
              `visited`, `O_snd`)
            - one-pass index deferred to S11
        - S8.2b DONE: CLI speaks IDs, suite green
            - post/like print ids; `refs/begs/beg-<id>`;
              like/get/reps/destroy take ids; list/dag print
              ids; dag `backs` from action files; get metadata
              from action file (`id` field)
            - post action gains `blob` (content = identity;
              fixes same-author/same-second collision)
            - tests: captures ARE ids; `CID(dir,id)` where git
              is poked directly; dag annotation sorted
        - S8.2c DONE: vote metadata dies; skel dies
            - like commit = its action file only; replay
              reads vote data from the action file
            - chains add generates `.gitattributes` +
              `random`; `cp -r skel` gone; skel deleted
            - tests: crafted votes forge action files
            - CAVEAT: send-path tests run the INSTALLED
              freechains (pre-receive hook uses PATH) --
              `make install` after recv-path changes
        - S8.4 POSTPONED -> lands with S15: receive validation
          (id/sign/time/backs, par.6)
            - rationale: replay still trusts only commit-derived
              facts (sig, %at, parents); file fields are
              display/vote-content -- validation belongs at the
              step that starts TRUSTING them (S15; the backs
              compare walks git via `backs()` until S11b)
            - includes the duplicate-ID net: identical action
              via two commits must dedup deliberately (skip
              re-apply), not overwrite/double-append
            - and id integrity: filename == blob sha (ls-tree)
    - S9: join commits: apply-before-commit, drop rollbacks,
      `beg~2` -> `beg~1`, destroy fixes (needs S8)
        - the forged-state fix (260803-forged-state.md) lands
          HERE: uniform per-commit state compare
        - done when rewritten `bug-forged-state` passes
        - S9.0 DONE: replay tolerance -- mode check accepts
          joined action commits (A|M on state.lua); PEAKS
          already shape-agnostic
        - S9.0b DONE: cleanups -- exact-status closed-set
          mode check (dispatch by A/AA/M/MM, refuse rest);
          COMMIT_ACTION asserts internally
        - S9.1 DONE: post joins (one commit: payload + action
          + state); apply BEFORE commit (ACTION.pre/.pos
          bracket it: nothing enters tree on failure, rollback
          gone); beg is one commit (post HEAD~1, like ref~1,
          destroy beg~1); BACKS includes action-commit tips;
          NOW(cid) shared writer/verifier `now` formula (FF
          state compare; joined tip folds own stamp over
          first-parent PEAK, never parent TIME); get
          commit_file excludes .freechains entirely
        - S9.1 tests: anatomy probes HEAD~1 -> HEAD; repl
          counts -1 per post; beg-merge ^2~1 -> ^2; err-post
          forge drops strip-state step; likes still 2 commits
          (probes kept until S9.2)
        - S9.2 DONE: votes join (one commit: action + state;
          beg merge carries both, MM on state.lua); like.lua
          mirrors post.lua: ACTION.pre -> apply -> merge/pos/
          WRITE -> one commit; rollback + state commit gone;
          tests: like probes HEAD~1 -> HEAD, err-like forge
          drops strip-state, sync/cli diagrams joined
        - S9.3 DONE: 1-parent pure state commits invalid
          ("invalid state : not a merge"); kills forged
          scenarios 1+2 by shape; cli-recv step 6 expects the
          shape error, step 7 resets to good state first;
          crafted trailing state commits in err-* stay (their
          action errors fire first, shape never reached)
        - S9.4 WON'T DO: superseded by S15 -- state leaves the
          tree, so nothing is transmitted to forge; the compare
          (and 260803-forged-state.md) die by removal
    - S10: payload eviction: `refs/payloads/<id>`, refspecs,
      clone, `--why` off post (needs S8)
        - `blob` identity half landed early at S8.2b
        - mode check final (with S15): one A/AA
          `actions/<hex>.lua` or EMPTY diff; parents classify
          (action/merge/genesis/invalid) -- par.5 literally
          total, no mode enumeration left
    - S11a DONE: delete trailers; structural classification
      (pulled BEFORE S9.4: commit() already pays the
      diff-tree; kind = action file's `action`; merge =
      2p no action; MM state.lua = state merge vs
      plumbing; 1p no action = invalid) (needs S9.3)
    - S11b: one-pass commit<->ID index (subsumes `ORD`,
      `COMMIT_ACTION`, `ACTION_COMMIT`) -- optimization,
      batches S11a's per-commit diffs (needs S11a)
        - sketch (implemented once, reverted to land WITH S11c:
          per-command full walk alone is not worth it):
          `INDEX(tips)` one `log --full-history --cc
          --diff-filter=A` walk fills `a2c`/`c2a`; `AID`/`CID`
          become lookups (full hashes only; sync ff `NOW(rem)`;
          `BACKS` rev-parses tips); lazy over HEAD, widened
          BEFORE first lookup (sync: `loc rem`; like on beg:
          `HEAD ref`); `ORD` dies; src `CID` moves to
          tst/tests.lua as `CID(dir, id)` with `--all` baked in
        - better id<->commit story for tests too: today
          `AID`/`CID` (tests) duplicate the src pair with
          divergent defaults (`--all`, dir param); want ONE
          parameterized solution both sides use
    - S11c: persist index in `.git/index.lua` (needs S11b)
        - `{ tips, a2c }` (`c2a` inverted on load); extend with
          `git log <tips-now> --not <tips-saved>`, rewrite on
          delta
        - facts immutable (a commit's tree never changes): no
          invalidation ever, destroy included
        - membership leaves the index: cache outlives resets and
          mixes refs, so get/destroy verify
          `merge-base --is-ancestor cid HEAD` per query
        - NOT in state.lua: local-only consumers; would draft
          plumbing into the S9.4 byte-compare and grow state
          by a hash per action (against S12)
        - prune (prune.md) invalidates it: saved tips die
          (`--not <dead>` errors) and entries map aids to
          pruned cids -> prune deletes the file; rebuilt
          lazily over the flattened history
        - lands right after S10 (S8.4/S10 shrink consumers
          first; par.7 shrinks more, later)
    - S12: shrink `posts` entries to `{maturity, reps, revoke}`
      (needs S8)
    - S13: revoke deletes payload ref; `gc` policy (needs S10)
    - S14 DONE (pulled before S9): naming pass `aid`/`cid`
        - CLI args: `hash`/`id` -> `aid` (get/like/destroy);
          get output field `id` -> `aid`; destroy error
          "invalid aid"
        - vars: `id`->`aid`, `hash`/`commit`->`cid` across
          chain/*.lua; apply takes `T.aid`/`T.cid`; git
          helpers' params -> `cid`
        - kept: `bid`/`tid` (aid-flavored locals), `ARGS.key`
          (reps: aid OR pubkey), tests' `AID`/`CID` helpers
        - design docs (.md) keep conceptual "id" prose
    - S15: state leaves the tree: one snapshot per commit in
      `.git/states/<cid>.lua` (local, derived, immutable,
      keyed by cid -- same nature as S11c's index)
        - writer and replay write the snapshot as each commit
          lands (cid known post-commit; no cycle: not in tree);
          `G_oct`, `PEAK`, destroy read `.git/states/<cid>.lua`
        - genesis snapshot at `chains add`
        - commits become pure action adds; merges pure topology:
          `merge=ours`, `.gitattributes`, M/MM mode checks,
          state-merge and "remote state mismatch" machinery die;
          S9.3 shape rule (1-parent no action = invalid) stays
        - mode check shrinks: legal diff = one A/AA action file
          (+ A payloads until S10); no M cases left
        - forged state impossible instead of checked (replaces
          S9.4); ff hardfork fail-fast becomes post-replay
        - like-on-beg derives the beg entry from its action file
          (no `show ref:state.lua`)
        - GC: hardfork settles history, octopus never sits below
          the settled window -> keep window + margin only;
          destroy below GC depth and fresh clones replay from
          genesis
        - costs: m loose O(m) files until GC (no delta
          compression); one snapshot write per replayed commit
        - prune (prune.md) must prune caches too: snapshots
          below the cut die; the prune-point snapshot is KEPT
          and rekeyed to the new orphan root (without it the
          flattened prefix must be replayed from its action
          files to reboot state)
        - reverses par.9's destroy argument and par.8's
          full-state-merge resolution
    - S6a: drop `.freechains/`: `actions/`, `genesis.lua`,
      `random` to root; shard `actions/ab/`
      (needs S10, S15)
        - BLOCKED before S10: user posts live at root; the
          prefix separates them (par.8 relies on "no user
          files left")
- branches:
    - `main`: fixes + design-neutral cleanups (S1, S4, S5)
    - `260803-redesign`: substrate + cluster (S2, S3, S6b, S8+)
    - criterion: useful even without the redesign -> `main`
- progress: substrate + S8 + S14 + S9.0-S9.3 + S11a done;
  S9.4 won't-do (superseded by S15);
  order: S15 (+S8.4) -> S10 -> S11b+S11c -> par.7 -> S6a;
  next: S15 (state leaves the tree)

## 11. Open questions

- **State out of the tree — RESOLVED: yes, as step S15.**

- **Cache `fronts` (inverse of `backs`)? RESOLVED: no store.**
  Impossible in action files (immutable, future-dependent);
  churn if committed (derivable, against S12); a `.git/` file
  saves nothing (rebuild needs no git, unlike the index).
  Derive in memory -- one O(n) inversion of `db[aid].backs` --
  when a consumer appears; today none exists.

- **When does deletion actually run?** `is_revoked` flips during
  replay, but dropping the ref mid-replay is destructive and hard
  to undo if the branch is later voided. Probably a sweep after
  the sync settles, never inside `commit()`.
- **`gc` policy.** Unreachable blobs survive until
  `git gc --prune`, and the default grace period is 2 weeks.
  Real deletion needs `--prune=now`, which is a policy call, not
  a default.
- **Does `--dag` need merge nodes?** It renders from `G.order`,
  which excludes them today. Confirm nothing regresses when they
  become entirely invisible to the DB.
- **Size limits.** `constants.lua` has a commented-out
  `post.size`. With payloads out of the tree this becomes a
  transport policy rather than a tree concern.
- **Full state merge — RESOLVED (§8), then reversed by S15.**
  Merged in-tree at S6b (one `state.lua` table, still current);
  leaves the tree entirely at S15. Until §7 lands, PEAK re-reads
  the snapshot per call — accepted.
