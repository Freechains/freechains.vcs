# Git History Flattening

## The Question

Is there a `git prune` command that takes a snapshot of the
current HEAD and discards the entire history, making the
result the new initial commit?

**Short answer:** No. `git prune` does something unrelated.
The correct tool is `git checkout --orphan`.

---

## What `git prune` Actually Does

`git prune` removes **unreachable objects** from the Git
object store — orphaned blobs, trees, and commits that are
no longer pointed to by any ref.
It is a garbage collection tool, not a history-flattening
one.

The higher-level command `git gc` calls `git prune`
internally as part of its cleanup cycle.
Neither command modifies branch history or creates snapshots.

### Common Misconception

> "I can use `git prune` to truncate history."

This is a widespread misunderstanding.
`git prune` only removes *unreferenced* objects; it never
modifies what referenced refs (branches, tags) point to and
has no mechanism to flatten or snapshot history.
The confusion likely arises from the word "prune" suggesting
tree trimming, whereas Git uses it strictly for object-store
garbage collection.

---

## The Correct Approach: `git checkout --orphan`

`--orphan` creates a new branch with **no parent commits**
(a true root commit).
Git pre-populates the index with the current working tree,
so the next commit becomes a standalone initial commit
containing the full snapshot of HEAD.

### Step-by-step

```bash
# 1. Create a parentless branch pre-loaded with current tree
git checkout --orphan fresh-start

# 2. Stage everything
git add -A

# 3. Commit — this is now a root commit with no history
git commit -m "Initial commit"

# 4. Remove the old branch
git branch -D main

# 5. Rename the orphan branch into place
git branch -m main

# 6. Force-push to remote (destructive — rewrites history)
git push --force origin main
```

### Key properties of `--orphan`

- The resulting commit has **zero parents** — it is a
  genuine root commit.
- The `.git` directory and all remote tracking configuration
  are preserved.
- It is fully scriptable and leaves the repository structure
  intact.

---

## Alternative: Nuke and Reinit

```bash
rm -rf .git
git init
git add -A
git commit -m "Initial commit"
git remote add origin <url>
git push --force origin main
```

Simpler but cruder:

- Destroys all remote tracking configuration (must be
  reconnected manually).
- Loses any local refs, stashes, hooks, and repo-level
  config in `.git/config`.
- Appropriate for throwaway or local-only scenarios.

---

## Relevance to Freechains

For **chain initialization or reset semantics**, `--orphan`
is the preferred model:

- Keeps the repository structure intact, which matters when
  Git repos are used as per-chain storage substrates.
- Produces a clean, deterministic root object — consistent
  with Freechains' requirement for a well-defined chain
  genesis block.
- Scriptable without tearing down `.git`, so hooks, remote
  config, and tooling remain in place across a reset
  operation.
- The orphan commit's hash is content-addressed and
  deterministic given the same tree, making it suitable as
  an anchor point in the Freechains DAG.
