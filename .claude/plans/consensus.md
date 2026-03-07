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

## Pipeline Summary

```
git fetch        — git validates objects + transport
    |
freechains       — validate signatures, reputation, DAG
    |
git merge        — integrate + pre-merge-commit hook
```
