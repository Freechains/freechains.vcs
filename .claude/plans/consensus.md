# Consensus: Fetch Validation Pipeline

## Git's Built-in Validation (fetch)

On `git fetch`, git validates automatically:

- **Object integrity** — SHA hash of every object matches
  content
- **Object graph** — commits reference valid parents, trees,
  blobs
- **Transfer protocol** — packfile checksums, no corruption

These guarantees are free — no freechains code needed.

## Freechains Validation (between fetch and merge)

After fetch, before merge, freechains must validate
consensus-level rules that git doesn't know about:

- **Signature verification** — GPG signatures on commits
- **Reputation thresholds** — author has enough reputation
- **DAG rules** — block acceptance per chain type
- **Genesis immutability** — genesis.lua must never change
  after chain creation

## Merge (after validation)

`git merge` integrates validated commits.
The pre-merge-commit hook (see merge-hook.md) runs as a
final safety net before creating the merge commit.

## Trust Levels

| Peer type | Fetch validation   | Merge              |
|-----------|--------------------|--------------------|
| Owner     | no-op (full trust) | direct merge       |
| Non-owner | signatures, rep, DAG | merge after pass |

Owner-to-owner replication skips freechains validation
entirely — both peers share the same key material and
trust each other fully.

Non-owner validation is future scope.

## Dry-run Merge Check

Before the real merge, a dry-run verifies mergeability:

```
git merge --no-commit --no-ff FETCH_HEAD
```

- Exit code 0 → merge would succeed (clean)
- Exit code != 0 → merge would fail (conflict or
  unrelated histories)

After checking: `git merge --abort` to clean up.
Only proceed to real merge if dry-run passes.

Note: `--abort` is only needed when `MERGE_HEAD` exists
(success or conflict). Unrelated histories rejection
leaves no merge state — no abort needed.

| Dry-run result       | MERGE_HEAD | Abort needed |
|----------------------|------------|--------------|
| Success (code 0)     | yes        | yes          |
| Conflict (code 1)    | yes        | yes          |
| Unrelated (code 128) | no         | no           |

## Pipeline Summary

```
git fetch                      — git validates objects
    |
freechains                     — validate signatures,
                                 reputation, DAG
    |
git merge --no-commit --no-ff  — dry-run merge check
git merge --abort              — clean up dry-run
    |
git merge                      — real merge
```
