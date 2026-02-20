# SQLite as a Companion Store

Git is excellent at DAG storage and sync, but **not at running queries or caching computed state**. SQLite fills that gap cleanly.

## What SQLite stores (and git doesn't)

```sql
-- Cached consensus linearization
-- Recomputed after each git fetch+merge, cheaply invalidated
CREATE TABLE consensus (
    chain    TEXT,
    position INTEGER,
    hash     TEXT,
    PRIMARY KEY (chain, position)
);

-- Cached reputation state at a known commit (checkpoint)
-- Avoids replaying from genesis on every sync
CREATE TABLE rep_checkpoint (
    chain       TEXT,
    at_hash     TEXT,   -- git commit hash this was computed at
    author_pub  TEXT,
    reps        INTEGER,
    PRIMARY KEY (chain, author_pub)
);
```

## The workflow

```
git fetch + git merge  ->  post-merge hook fires
                       ->  detect new commits (rev-list old..new)
                       ->  skip freechains-sync commits
                       ->  walk remaining commits in date-order
                       ->  apply reputation deltas from checkpoint
                       ->  update rep_checkpoint
                       ->  recompute consensus order
                       ->  overwrite consensus table
```

## Why not store everything in git

- Reputation is a **running aggregate** — the result of replaying history. Git has no concept of memoizing intermediate computation.
- Querying `SELECT * FROM consensus ORDER BY position` is instant. Walking `git log` for every read is not.
- The consensus table is a **write-through cache**: cheap to invalidate, fast to read.
- If SQLite is deleted, it can be fully reconstructed by replaying git history — git is always the source of truth.

## The clean separation

| Concern | Tool |
|---|---|
| Block payload storage | Git blob |
| DAG structure | Git commit graph |
| Peer sync | Git push/fetch + merge / git daemon |
| Block validation on receive | `pre-receive` git hook |
| Post-sync processing trigger | `post-merge` / `post-receive` git hook |
| Bootstrap / relay | GitHub (public) or self-hosted GitLab |
| Consensus cache | SQLite |
| Reputation checkpoint | SQLite |
| Application / consensus logic | Lua |
