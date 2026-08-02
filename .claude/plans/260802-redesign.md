# Redesign: Lua Database as the Action Layer

Four changes that compose into one:

1. **Join** the action and state commits into a single commit
2. **Flatten** `.freechains/likes/`, `.freechains/revokes/` into
   `actions/<id>.lua` — one file per action, kind-agnostic, and
   no longer hidden
3. **Self-describe** each action with `action` and `backs`, where
   `backs` holds *action IDs*, not commit hashes
4. **Evict payloads** from the tree into ref-anchored loose blobs

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

  `chains add --clone` (chains.lua:158) must pass an explicit
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
incoming action file *is* new relative to parent 1. get.lua:23
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

`.freechains/` existed to keep internal files out of the user's
way. With payloads evicted (§3) there are no user files left, so
the prefix hides nothing from anyone. Drop it — but keep the
grouping, because the objection was the hiding, not the
structure:

```
actions/              <id>.lua, one per action (sharded below)
state/                authors, posts, order, now
genesis.lua           chain definition
random                uniqueness seed
.gitattributes        state/** merge=ours
```

Five entries, self-describing: `ls` now says what the repo is.

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
sync.lua:243-275.

**Filename collisions disappear.** post.lua:16-22 and :30-37
error when a payload name is taken. With no payload in the tree
there is no name and no collision.

**Closes an existing hole.** Replay never compares its recomputed
state against what a commit carries. `commit()` (sync.lua:328-335)
checks only `PEAK`; the full comparison happens once, in the
fast-forward path (sync.lua:443-452), and never in the diverge
path. So a commit carrying forged `authors.lua` passes the mode
check and is merely passed through — and `G_oct` is then loaded
straight from a commit tree (sync.lua:363-374). Joining makes
every commit a state commit, so the comparison becomes uniform
and cheap. It should land with this, not after.

**The signing key must be read before committing.**
`ssh.pubkey` parses a signature out of an existing commit, so it
cannot supply `sign` any more. `--sign` is a private key path
(`--sign="$KEYS/alice"`) and the canonical pubkey form is the
first two fields of the `.pub` file (guide.sh:86). There is no
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

1. `db.lua`: build the action file, `git hash-object` for the ID,
   load/cache the DB, build the commit <-> ID index from tree
   diffs (§5) — this replaces `trailer()` and must run before
   replay
2. `apply`: `T.hash` -> `T.parents`; key on `T.id`; peak folded
   over `backs`; duplicate-ID check as a net
3. Layout (§8): `.freechains/{likes,revokes}/` -> `actions/`,
   `.freechains/state/` -> `state/`, `genesis.lua` and `random`
   to the root, `tmp/` into `.git/`; delete `.gitignore` and all
   three `.gitkeep`s; skel ships no `actions/` at all; update
   every path in chains.lua and common.lua
4. `post.lua` / `like.lua`: payload blob anchored under a temp
   ref then renamed to `refs/payloads/<id>`, build file, derive
   ID, apply, write file + state, one signed commit; drop the
   `reset --hard` rollbacks and the filename-collision checks;
   pubkey from the `.pub` file; `post` loses `--why`
5. `sync.lua` `commit()`: merged mode check, the parent-count
   classification, and the four validations — ID vs blob hash,
   `backs` vs git ancestry, `sign` vs signature, `time` vs
   `%at` — plus the state comparison
6. `sync.lua`: `refs/payloads/*` in both refspecs; post-fetch
   deletion of revoked payload refs; drop the trailing state
   commit after merge (sync.lua:567-580) and the content-conflict
   path (sync.lua:506-515)
7. `chains.lua`: explicit `refs/payloads/*` (and `refs/begs/*`)
   refspec on `--clone` (chains.lua:158) — without it a cloned
   chain loses every payload at the first prune
8. `get.lua` / `list.lua` / `reps.lua`: read the DB, delete
   `commit_file()`, `backs()`, `trailer()`, the `--is-ancestor`
   membership check, and the `why` trailer-stripping gsub
   (get.lua:54)
9. `revoke`: delete `refs/payloads/<id>` once `is_revoked`, and
   `gc` policy
10. Tests: hashes -> IDs throughout

Steps 1-2 are self-contained and can land alone.

## 11. Open questions

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
