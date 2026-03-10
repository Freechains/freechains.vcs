# Error Format

All error messages use:
`ERROR : <command> : <detail>`

Examples:
- `ERROR : chains add : git init failed`
- `ERROR : chains rem : not found: x`
- `ERROR : chain post : git commit failed`

# exec Format

With error message:

```
exec (['stderr',]
    "command"           -- one line
    , "error message"   -- one line
)
```

With `"bug found"` flag:

```
exec (true, ['stderr',]
    "command"           -- one line
)
```

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
| `merge.md`       | Merge ordering, veto, owner-driven hard fork   |
| `consensus.md`   | Fetch validation pipeline                      |
| `reps.md`        | Reputation: likes, dislikes, pioneers, 12h rule|
| `crypto.md`      | Crypto choices (openssl, luasodium)            |
| `commands.md`    | Freechains CLI to Git command mapping          |
| `tests.md`       | Test catalog (58 tests across sections A–X)    |
| `merge-hook.md`  | Pre-merge-commit consensus verification        |
| `metadata.md`    | Data inventory: local/shared, mutable/immutable |
| `threats.md`     | Security threat catalog (T1–T6), mitigations   |
