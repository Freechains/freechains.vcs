# Git Merge & Freechains

---

## 1. Git Merge Internals

### Parent ordering (invariant)

A merge commit has exactly two parents:
- **First parent** (`^1`) = local HEAD before merge
- **Second parent** (`^2`) = remote FETCH_HEAD

This is a **git invariant**, not a convention. Immutable
after the merge. Any peer can recover which side was local
and which was remote:

```bash
git show <merge>^1   # local branch
git show <merge>^2   # remote branch
git cat-file -p <merge>   # raw: "parent <hash1>" then "parent <hash2>"
```

After propagation: when peer C fetches from peer A (who
already merged B's content), C sees A's merge commit with
A's parent ordering intact. C then creates its own merge.
The chain preserves local/remote distinction at each hop.

### Strategies (`-s`)
- **`ort`** (current default): detects renames, handles criss-cross merges well.
- **`recursive`**: old default, recursive three-way merge.
- **`resolve`**: simplest, single common ancestor.
- **`octopus`**: multiple branches at once, no manual conflicts.
- **`ours`**: ignores the other branch entirely — keeps HEAD as-is.
- **`subtree`**: variant of `ort` for directory subtrees.

### Tiebreak Options (`-X`)
Apply **only to conflicting hunks** — non-conflicting changes merge normally.

- **`-X ours`**: on conflict, HEAD side wins.
- **`-X theirs`**: on conflict, merged branch side wins.
- **`-X ignore-space-change`** / **`ignore-all-space`**: ignores whitespace differences.

> **Important distinction:**
> | Mechanism | Scope |
> |---|---|
> | `-X ours` / `-X theirs` | Only resolves conflicting hunks |
> | `-s ours` | Discards everything from the other branch |

### Merge Attributes (`.gitattributes`)
Per-file-type merge drivers: `text`, `binary`, `union` (concatenates without conflict), `ours`, or custom external drivers.

### Rerere
`git rerere` memorizes conflict resolutions and reapplies them automatically — useful for repeated rebases.

---

## 2. Detecting Conflicts Before Merge

### `git merge-tree` (best option)
Performs the merge virtually, without touching the working tree:

```bash
git merge-tree --write-tree HEAD target-branch
echo $?   # 0 = no conflict, 1 = has conflict
```

Fully available from Git 2.38+. Ideal for automation and CI.
**Not available on Git 2.34** (current target). Use the
`--no-commit --no-ff` approach below instead.

### `--no-commit --no-ff`
Performs the merge but does not commit — allows inspection before confirming:

```bash
git merge --no-commit --no-ff target-branch
git diff --cached
git merge --abort   # undo everything
```

### `git diff` between branches
Shows divergences (does not detect conflicts directly):

```bash
git diff HEAD...target-branch
```

---

## 3. Freechains Merge Semantics

### Merge = sync event

- Merges are always `--no-ff` — an explicit merge commit
  is created every time
- The merge commit is a **sync event**: "peer X integrated
  remote content at time T"
- `Freechains-Peer: <pubkey>` trailer identifies the peer
  (see [trailer.md](trailer.md))
- GPG signing (`-S`) makes it a signed attestation
- Merge commits are currently **skipped** in reputation
  computation ([reps.md](reps.md))
- The `pre-merge-commit` hook runs consensus checks before
  the merge is finalized

### `--no-ff` requirement

Fast-forward merges do not create a merge commit, so the
`pre-merge-commit` hook **does not fire**. All freechains
merges must use `--no-ff`:

- **Preserves topology** — the group of commits that entered
  together is visible as a unit. Fast-forward hides the
  branch in linear history.
- **Explicit merge point** — a concrete commit where
  integration happened. Anchor for hooks, audits, and
  consensus proofs.
- **Atomic record** — the merge commit can carry metadata
  (who merged, when, consensus proof) in the message or
  trailers.
- **Clean revert** — reverting a `--no-ff` merge is one
  commit. With fast-forward, each commit must be reverted
  individually.
- A merge in a chain is a **deliberate consensus event**,
  not just "advance the pointer." The merge commit *is* the
  consensus record.
- Fast-forward would imply commits were already accepted —
  skipping the entire validation stage.

### `pre-merge-commit` hook

Runs after the merge commit is prepared but before it is
finalized. Exiting with non-zero aborts the merge.

```bash
# .git/hooks/pre-merge-commit
#!/bin/sh
if ! ./scripts/check-consensus.sh; then
  echo "Consensus check failed. Merge aborted."
  exit 1
fi

# Reject fast-forward (no merge commit)
if [ -z "$GIT_MERGE_HEAD" ]; then
  echo "Fast-forward detected. Use --no-ff for Freechains merges."
  exit 1
fi
```

Other relevant hooks:
- **`pre-receive`** (server-side) — runs on the server
  before any ref is updated. Ideal for centralized workflows.
- **`update`** (server-side) — similar to `pre-receive`,
  but per branch. More granular.

### Sync flow

```
unstage (restore tracked files, reset local/now.lua)
git fetch <remote> <branch>
git merge --no-commit --no-ff FETCH_HEAD   # dry-run
git merge --abort                          # clean up
git merge --no-edit FETCH_HEAD             # real merge (--no-ff)
```

- Never use `git pull` (bypasses validation)
- Fast-forward skips `pre-merge-commit` hook → must be
  rejected (see merge-hook.md)
- **Unstage required**: `stage()` (local-staging.md)
  writes to tracked `reps/` and `time/` files without
  committing, leaving a dirty working tree.
  Before fetch/merge:
  `git checkout -- .freechains/reps/ .freechains/time/`
  and reset `local/now.lua` to 0.
  After merge, next `stage()` re-scans from merged state.

### Strategies Are Equivalent Without Conflict

When there is **no conflict**, all merge strategies (`ort`,
`recursive`, `resolve`) produce the **same tree** — every
file from both sides is included. `-X ours`/`-X theirs` are
also irrelevant (no conflicting hunks to tiebreak). The only
strategy that behaves differently without conflict is
`-s ours`, which discards the other side entirely.

This means: for conflict-free merges, strategy choice does
not matter. The default (`ort`, Git 2.34+) is fine.

### Conflict Resolution by Reputation

```
1. merge-tree --write-tree HEAD target-branch
       │
       ├── exit 0 → no conflict → normal merge
       └── exit 1 → conflict → consult reputation
                                        │
                                ours > theirs?
                                   ├── yes → -s ours
                                   └── no  → read-tree hack
```

When a conflict is detected, the **entire losing branch is
discarded** — not just the conflicting hunks. This uses
full-branch rejection:

- **Ours wins** → `-s ours` (native git, discards remote)
- **Theirs wins** → read-tree hack (no `-s theirs` in git)

The read-tree hack creates a merge commit whose tree is
entirely from the remote side:

```
git merge --no-commit -s ours FETCH_HEAD
git read-tree --reset -u FETCH_HEAD
git commit
```

### No `-s theirs` in Git

Git has **no `-s theirs` strategy**. `-s ours` exists
(discards the other branch entirely), but there is no
symmetric counterpart. The read-tree hack above is the
standard workaround.

Alternative: **reverse the actor** — the remote peer merges
with `-s ours` (discarding the local side), then the local
peer fast-forwards. Requires the remote to be the one
performing the merge.

### Paper vs Git-Based Merge

The original paper and the git-based implementation differ
in conflict rejection scope:

| Aspect    | Paper                         | Git                           |
|-----------|-------------------------------|-------------------------------|
| Conflict  | Reject commits from the other | Reject the **entire** other   |
| rejection | branch **from the conflicting | branch — including commits    |
|           | commit onward** (earlier      | **before** the conflicting    |
|           | commits are kept)             | commit                        |

In the paper, if branch B has commits [b1, b2, b3] and b2
causes a conflict, only b2 and b3 are rejected — b1 is
kept. In git, `-s ours` (or the read-tree hack) discards
the entire branch: b1, b2, and b3 are all rejected.

This is a fundamental difference: git merge operates on
**whole branches**, not individual commits. There is no
built-in way to accept some commits from a branch and
reject others during a merge.

### Merge Block

The merge commit must record in metadata whether there was
a conflict and who won, allowing other peers to verify the
decision independently:

```
merge-block:
  parents: [hash-A, hash-B]
  conflict: true | false
  winner: "ours" | "theirs" | null   # null if no conflict
  rep-ours: 42
  rep-theirs: 31
```

### Considerations

**Determinism is critical.** All peers must reach the same
decision. Two approaches to guarantee this:
- The reputation used for tiebreaking is **snapshotted at
  block time** and recorded in the block.
- Or reputation is computed **up to the common ancestor**
  (consensus point between both sides), avoiding divergence
  caused by different local state.

**Reputation tie** requires a deterministic secondary
tiebreaker, e.g.: block hash, timestamp, or lexicographic
order of authors.

**Auditability:** recording `rep-ours` and `rep-theirs` in
the block lets any peer audit the decision later, even if
reputation has changed since then.

**Whole-branch rejection vs paper semantics:** the conflict
resolution diagram uses `-s ours` / read-tree hack, which
discard the entire losing branch. The paper only rejects
commits from the conflicting commit onward. See "Paper vs
Git-Based Merge" above — this is an accepted divergence.

---

## 4. Merge Voting — Likes/Dislikes on Merge Commits

**Status**: NOT REVIEWED — idea dump, not a design.

### Mechanism

1. Merge commits become **votable objects** — peers can
   post likes/dislikes targeting a merge commit hash
   (using `Freechains-Ref: <merge-hash>`)

2. Dislikes accumulate against the merge. If they cross
   a threshold (analogous to post-ban), the merge is
   **rejected**:
   - The merge commit and all commits reachable only
     through the second parent (remote side) are dropped
   - History reverts to the first parent (local side)
   - Any commits built on top of the merge are also
     dropped (they reference a rejected base)

3. "Dropped" means: for consensus computation, the merge
   and its remote-only descendants are treated as if they
   never existed. The DAG still contains them (git doesn't
   delete objects), but the consensus walk ignores them.

### Why first-parent ordering matters

The rollback is well-defined **because** git preserves
parent ordering. "Drop the merge" always means "keep
local, reject remote." Without this invariant, you
wouldn't know which side to keep.

### What this enables

- **Collective veto on sync events**: if someone syncs
  with a malicious peer and brings in spam/attacks, the
  community can vote to undo it
- **Retroactive defense against T2a**: a merge that
  brought in backdated posts can be voted out after the
  fact — the merge-witness timestamp idea (threats.md)
  makes the manipulation visible, and merge voting
  provides the enforcement mechanism
- **Accountability**: the `Freechains-Peer` trailer
  identifies who performed the merge. Repeated bad merges
  → pattern of bad judgment → peers stop syncing with
  that node

### Open questions (NOT REVIEWED)

1. **Threshold**: Same as post-ban? Different? Should it
   scale with the amount of content in the merge?

2. **Cascading drops**: If merge M1 is dropped, and merge
   M2 was built on top of M1, M2 must also be dropped.
   But M2 might have brought in legitimate content too.
   Is this acceptable collateral?

3. **Timing**: Can a merge be voted out at any time, or
   only within a window (e.g., 24h)? Unbounded voting
   means old consensus can be retroactively disrupted.

4. **Who can vote**: Anyone with reputation? Only peers
   who have the merge in their DAG? Only peers who
   were "online" (had recent activity) when the merge
   happened?

5. **Determinism**: All peers must agree on whether the
   merge is dropped. The threshold check must be
   deterministic — same inputs, same decision. This
   means the vote tally must be computed at a consistent
   DAG state.

6. **Interaction with consensus ordering**: Dropped merges
   change the DAG topology → change `--date-order`
   traversal → change reputation → potentially change
   other vote tallies. Circular dependencies?

7. **Attack surface**: Could merge voting itself be
   weaponized? A cabal with sufficient reputation could
   vote to drop legitimate merges, effectively censoring
   content. This is the same problem as dislike-based
   censorship on posts — does the threshold provide
   adequate protection?

8. **Recovery**: After a merge is dropped, can the remote
   content be re-merged later (by a different peer, or
   after the attacker's posts are individually disliked)?
   Or is it permanently excluded?

---

## 5. Relationship to Other Mechanisms

| Mechanism              | Scope           | Timing      |
|------------------------|-----------------|-------------|
| 12h penalty on posts   | Individual post | Preventive  |
| Dislike on posts       | Individual post | Reactive    |
| Merge-witness timestamp| Detection       | At merge    |
| **Merge voting**       | **Entire sync** | **Reactive**|
| Consensus ordering     | Branch priority | At merge    |

Merge voting is the only mechanism that operates at the
**sync-event granularity** rather than individual posts.
It's a coarser tool — a nuclear option for when an entire
batch of incoming content is bad.

---

## 6. Distributed Merge Properties

### Non-Determinism of Merge Commit Hashes

When two peers independently produce a merge of the same
logical tips, their resulting merge commit SHAs will differ:

```
Peer A: merge(x, y) → z_A
Peer B: merge(x, y) → z_B

SHA(z_A) ≠ SHA(z_B)
```

Git's commit hash is computed over the full commit object,
which includes author, committer, and timestamp fields. Two
independent peers cannot produce the same SHA for a newly
minted commit object, even if the tree and parent references
are identical.

**This is not a problem for Freechains.** The protocol
requires content agreement, not pointer agreement.

### Tip Divergence is Normal

When both peers are actively producing data:

- Peer A and peer B will independently merge divergent tips
  and produce different merge commit hashes
- Both peers will have the same content reachable from their
  respective tips
- Their local tip pointers will differ

This is expected behavior. Tip divergence between active
peers is not a failure state. The protocol only requires:

- Content is eventually shared across peers via gossip
- Rep-based conflict resolution is deterministic so peers
  independently reach the same content
- **Idle peers converge** by fast-forwarding to the remote
  tip

Eventually one side becomes idle and fast-forwards to the
remote, achieving tip convergence. There is no need for a
globally canonical tip hash at any point.

### The "Recursion" Non-Problem

A concern can be raised that tip divergence leads to
recursive merging:

```
Round 1: A merges (a, b) → x;  B merges (b, a) → y
Round 2: A merges (x, y) → z_A;  B merges (x, y) → z_B
Round 3: ...
```

This recursion is not a problem because:

- Each round the set of content commits is finite and
  already shared
- Git's content-addressing guarantees no commit is
  duplicated — a commit appearing in multiple branches
  appears exactly once as an object
- What differs across peers is only DAG traversal order,
  not content
- The recursion terminates naturally as peers become idle
  and fast-forward
- No canonical tip hash is required at any round

### Back-Compatibility with Vanilla Git

| Operation                  | Compat | Notes                        |
|----------------------------|--------|------------------------------|
| `git clone` / `git fetch`  | Yes    | Freechains commits are valid |
| `git log`, `git show`      | Yes    | Extra headers preserved      |
| `git push` (vanilla client)| No     | Missing headers + signature  |
| `git merge` (vanilla)      | No     | Unsigned, headerless commit  |

Read compatibility is high. Write compatibility is
intentionally broken at the transport boundary via Git hooks
(`pre-receive`, `update`), which enforce Freechains protocol
invariants.

### Key Conclusions

- **Merge commits are necessary** when both branches'
  histories must be preserved. Fast-forwarding to the winner
  would silently drop the other branch's commits from
  reachable history.
- **Non-deterministic merge commit hashes are not a
  problem** because Freechains requires content agreement,
  not tip hash agreement.
- **Tip divergence between active peers is normal** and
  resolves naturally when one side becomes idle and
  fast-forwards.
- **Rep-based ours/theirs resolution is deterministic** —
  any peer given the same inputs reaches the same content,
  independent of merge commit hash.
- **Git fast-forward remains the consensus-safe operation**
  for idle peers converging on a remote. Merge is used only
  when actively integrating divergent tips.
- **The losing branch is only discarded on merge failure**,
  not on merge success. Ours/theirs is a conflict resolution
  strategy, not a branch deletion strategy.

---

## 7. Merge Strategies & Consensus Implications

### Why Merge Breaks Consensus

When two peers independently run `git merge` on the same
pair of branches, the result can differ depending on:

- The merge **strategy** chosen (`recursive`, `ort`,
  `octopus`…)
- The **local commit ordering** (which may differ between
  peers after sync)
- **Conflict resolution** — if conflicts exist, each peer
  may resolve them differently, producing a merge commit
  with a **different hash**

After sync, a chain has multiple HEADs. To get a canonical
HEAD, someone must create a merge commit. But:

1. Any peer can create that commit → different hashes →
   forks
2. The merge commit itself needs signing → only the chain
   owner can sign → **centralization**
3. Two peers synchronizing independently produce different
   merge commits even with identical content → **chain
   split**

### Consensus Requires Total Order

Git merge produces **partial order** — it says "X and Y
converged into Z", but says nothing about which of X or Y
came "first" globally. For Freechains:

- **Likes/dislikes** depend on ordering: the same block
  receiving a like before or after a reputation threshold
  produces different outcomes
- **Spam resistance** depends on cumulative counts — order
  matters
- Merge gives no guarantee that all peers calculate the same
  reputation for the same block

### Merge Options vs Consensus

#### `--ff` (fast-forward)

No merge commit is created — Git just moves the HEAD
pointer.

```
Before:  A - B - C  (main)
                  \
                   D - E  (feature)

After:   A - B - C - D - E  (main)
```

**For consensus:** the only safe Git merge operation.
Deterministic, no new commit, preserves existing hashes.
But it only applies when linearity already exists.

#### `--no-ff` (explicit merge commit)

Always creates a merge commit even when fast-forward would
be possible. The merge commit hash depends on timestamp,
author, and resulting tree — **non-deterministic between
peers.**

#### `--squash`

Collapses all commits from the source branch into a single
new commit. **Worse than `--no-ff`** — loses the identity
of original commits entirely. Any peer that had them
individually can no longer reconcile with the squashed
state.

### Rebase — The Most Dangerous Operation

Rebase **rewrites commits** — it takes commits from one
branch and re-applies them on top of another point,
producing **new commits with new hashes.**

```
Before:  A - B - C  (main)
              \
               D - E  (feature)

After:   A - B - C - D' - E'  (feature)
```

`D'` and `E'` carry the same content as `D` and `E` but
are **entirely different objects** with different hashes.

| Variant              | Description                       |
|----------------------|-----------------------------------|
| `git rebase`         | Linear, replays commits one by one|
| `git rebase -i`      | Interactive — reorder, squash, edit|
| `git rebase --onto`  | Rebase onto arbitrary point       |

**For consensus:** rebase violates the immutability that
Freechains requires. If one peer rebases and another does
not, the same content blocks have different hashes — the
DAG diverges irreconcilably. There is no recovery path
without treating one peer's history as authoritative.

### Three-Way Merge Algorithm

For every file, Git compares three versions: the common
ancestor (BASE), side A, and side B:

| BASE | A | B | Result          |
|------|---|---|-----------------|
| X    | X | X | X (no change)   |
| X    | Y | X | Y (only A changed) |
| X    | X | Y | Y (only B changed) |
| X    | Y | Y | Y (both same)   |
| X    | Y | Z | **CONFLICT**    |

### `recursive` Strategy

When there are multiple common ancestors (multiple LCAs),
merge them **first** to produce a virtual common ancestor,
then run a normal three-way merge using that synthetic base.

```
Common ancestors: M1, M2

Step 1: merge(M1, M2) → VIRTUAL_BASE
Step 2: three-way merge(A, B, VIRTUAL_BASE)
```

This can recurse — if M1 and M2 also have multiple common
ancestors, the process repeats. Hence the name.

The virtual merge is temporary, exists only in memory.
But it **can have internal conflicts** resolved
automatically using `ours` — which introduces **silent
bias** depending on which branch is considered "current".

### `ort` Strategy (Ostensibly Recursive's Twin)

Introduced in Git 2.34 as a drop-in replacement for
`recursive`. Conceptually identical — same LCA, same
virtual ancestor — but completely reimplemented.

`recursive` had a fundamental architectural flaw: it
**modified the working tree and index** during the merge
calculation itself. `ort` cleanly separates merge
calculation from filesystem application:

```
recursive:  calculate → apply → calculate → apply
ort:        calculate everything → apply everything
```

Concrete improvements: more accurate rename detection,
explicit rename/rename and rename/delete conflict handling,
improved submodule merges, better performance.

### Why `recursive`/`ort` Are Non-Deterministic

Two peers with identical history can arrive at **different
virtual ancestors**:

1. **Order of LCA merging** — if there are 3 LCAs, the
   order in which they are merged pairwise affects the
   result; the spec does not mandate a canonical ordering
2. **Internal conflict resolution** — conflicts inside the
   virtual merge are resolved with `ours`, which depends on
   which branch is "current" — and that depends on the
   peer's local checkout state

Different virtual ancestors → different merge base →
different conflict resolution → different merge commits →
**different hashes**.

### Summary: Operations vs Consensus

| Operation            | New hash? | Preserves history? | Deterministic? |
|----------------------|-----------|--------------------|----------------|
| fast-forward merge   | No        | Yes                | Yes            |
| `--no-ff` merge      | Yes       | Yes                | No             |
| `--squash` merge     | Yes       | No                 | No             |
| rebase               | Yes       | Partially          | No             |
| `recursive` / `ort`  | Yes       | Yes                | No             |

### Architectural Consequence

**Fast-forward is the only Git merge operation compatible
with consensus** — and it only applies when no divergence
exists, meaning the chain is already linear.

- Git must be used strictly as **transport and immutable
  block storage**
- All DAG ordering logic — resolving multiple HEADs after
  sync, determining canonical sequence, computing
  reputation — must live in the **Freechains protocol
  layer**, outside Git
- Git hooks may trigger Freechains processing, but Git
  itself must never be asked to resolve divergence

This mirrors the approach taken by Radicle: avoid merge
entirely, work with independent refs, and let the
higher-level protocol define what "current state" means.

---

## Related Plans

- [trailer.md](trailer.md) — `Freechains-Peer:` on merges
- [threats.md](threats.md) — T2a merge-witness timestamps
- [reps.md](reps.md) — Reputation computation (skips merges)
- [consensus.md](consensus.md) — Fetch → validate → merge
