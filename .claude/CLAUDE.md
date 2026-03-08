# Design Documents

Key specs in `.claude/plans/`:

| File             | Topic                                         |
|------------------|-----------------------------------------------|
| `all.md`         | Architecture overview and design rationale     |
| `git.md`         | Git as database: commit fields, DAG traversal  |
| `genesis.md`     | Deterministic genesis block specification      |
| `chains.md`      | Chain types, identification, synchronization   |
| `layout.md`      | Filesystem layout: config/ + chains/           |
| `replication.md` | Owner vs non-owner sync rules                  |
| `signing.md`     | GPG signing via `git commit -S`                |
| `consensus.md`   | Fetch validation pipeline                      |
| `crypto.md`      | Crypto choices (openssl, luasodium)            |
| `commands.md`    | Freechains CLI to Git command mapping          |
| `tests.md`       | Test catalog (58 tests across sections A–X)    |
| `merge-hook.md`  | Pre-merge-commit consensus verification        |
