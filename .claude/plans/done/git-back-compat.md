# Git Back-Compatibility

## Design Goal

Freechains repos are valid git repos.
Vanilla git users can clone, work, modify, commit, and push
back — without installing Freechains or knowing about it.

## Read Path (vanilla git → Freechains repo)

```
git clone <freechains-peer>/<chain>
git log
git show <hash>
```

Freechains commits are valid git commits.
Extra headers/trailers are preserved by git but invisible
to unaware users.
The `.freechains/` directory is visible but does not
interfere with normal git operations.

### Compatibility

| Operation               | Works | Notes                           |
|-------------------------|-------|---------------------------------|
| `git clone`             | yes   | Full repo with history          |
| `git fetch`             | yes   | Standard git protocol           |
| `git log`, `git show`   | yes   | Extra headers preserved         |
| `git diff`              | yes   | Content diffs work normally     |
| `git blame`             | yes   | Per-line attribution works      |

The `.freechains/` metadata changes on every commit
(authors.lua, posts.lua).
This is visible in `git log` but does not affect user
content files.

## Write Path (vanilla git → push to Freechains)

```
git clone <freechains-peer>/<chain>
# edit files, commit normally
git push origin main
```

A vanilla commit has:
- No Freechains signing headers
- No `.freechains/` metadata updates
- Standard git author/committer fields
- No reputation context

### Push as `--beg`

The Freechains daemon receives a push with commits it does
not recognize as Freechains-native.
It treats them as **`--beg` posts** — blocked, pending
approval.

This means vanilla git users can contribute to public
chains without installing Freechains.
Their posts start as blocked/beg and require approval
from someone with reputation.

### Detection

The daemon distinguishes Freechains-native commits from
vanilla commits by the absence of protocol-specific
headers/trailers.
Any commit without Freechains signing metadata is
classified as a beg post.

## Preview: Seeing Blocked Posts

A vanilla git user pushes, it becomes a beg/blocked post.
The user needs to **see their own post as if it were
accepted** — otherwise they push and see nothing.

This connects to the input/output branch model
(see [replication.md](replication.md)):

- **output branch**: accepted posts only (what others see)
- **input branch**: includes blocked/beg posts (what the
  author sees)

### Option 1 — Staging branch

Accept the push to a separate branch (e.g., `beg/<hash>`
or `input`), not `main`.
The user's `git log` on that branch shows their post.
Other peers only see `main` (output).

### Option 2 — Accept to main, mark as blocked

The commit is in git history on `main`, but Freechains
consensus skips it until approved.
Vanilla `git log` shows it naturally.
More git-compatible — the user does not need to know about
special branches.

## Open Questions

### Push mechanics

1. How does the daemon distinguish a Freechains-native
   commit from a vanilla commit?
   Absence of specific headers/trailers?
2. The vanilla commit won't update `.freechains/authors.lua`
   or `.freechains/posts.lua`.
   Does the daemon create a wrapper commit that adds the
   metadata? Or does it amend the received commit?
3. A vanilla push might contain several commits.
   Each one becomes a separate beg post?
   Or the whole push is one beg?
4. The vanilla user might modify `.freechains/` files
   (accidentally or on purpose).
   Should the daemon reject commits that touch
   `.freechains/`?
5. The vanilla user might have merged locally.
   How does the daemon handle merge commits from
   non-Freechains sources?

### Visibility

6. Who approves a beg post?
   A pioneer or author with reputation does a like?
   Or is there an explicit `unblock` command?
7. When syncing, do blocked/beg posts travel to other
   peers? (See replication.md — begs can be transmitted
   "to some extent".)
8. Can a vanilla `git log` / `git show` make sense of
   the repo?
   The `.freechains/` metadata changes on every commit —
   is that noise or useful?
9. When a vanilla user clones, they get the full repo
   including `.freechains/`.
   Should there be a `.gitattributes` or docs explaining
   those files?

### Lifecycle

10. If a beg is never approved, does it stay in git
    history forever?
    Or is there a pruning mechanism?
    (See [prune.md](prune.md))
11. If a beg is approved, does the original vanilla commit
    stay as-is, or is it replaced by a Freechains-native
    commit with proper metadata?

## Existing Compatibility Notes

From [merge.md](merge.md):

| Operation                   | Compat | Notes                        |
|-----------------------------|--------|------------------------------|
| `git clone` / `git fetch`   | yes    | Freechains commits are valid |
| `git log`, `git show`       | yes    | Extra headers preserved      |
| `git push` (vanilla client) | no*    | Missing headers + signature  |
| `git merge` (vanilla)       | no*    | Unsigned, headerless commit  |

*With push-as-beg, vanilla push becomes compatible
(accepted as blocked post instead of rejected).
Vanilla merge remains incompatible at the protocol level
but could follow the same beg pattern.

## Related Plans

- [replication.md](replication.md) — Input/output branches
- [merge.md](merge.md) — Back-compat table, merge rules
- [signing.md](signing.md) — SHA-1 caveat, signature model
- [consensus.md](consensus.md) — Fetch validation pipeline
- [prune.md](prune.md) — History pruning
