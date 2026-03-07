# Replication: Owner-to-Owner

## Current scope

Owner-to-owner replication only.
Full trust, no validation, no consensus.
Chains use working trees (`git init`, not bare repos).

## Workflow

```
Host A:  create chain, post signed block
Host B:  git clone chain from A, post signed block
Host A:  git fetch from B, validate, git merge (gets B's block)
```

## Git operations

### Host B joins chain from Host A

```bash
git clone <A>/chains/<hash>/ <B>/chains/<hash>/
ln -s <hash>/ <B>/chains/<alias>
```

`git clone` copies the full repo including history.
The symlink gives it a human-readable alias on B.

### Host A syncs from Host B

```bash
git -C <A>/chains/<hash>/ remote add hostB <B>/chains/<hash>/
git -C <A>/chains/<hash>/ fetch hostB main
# validate fetched commits (signatures, reputation, DAG rules)
git -C <A>/chains/<hash>/ merge FETCH_HEAD
```

`git pull` is wrong for consensus — it merges automatically
before any validation can occur.
The correct flow is: fetch → validate → merge.
Since both hosts diverged (each posted independently),
the merge produces a merge commit on A.

### Host B syncs from Host A

```bash
git -C <B>/chains/<hash>/ fetch origin main
# validate fetched commits
git -C <B>/chains/<hash>/ merge FETCH_HEAD
```

B already has A as `origin` from the clone.

## Two trust levels (future)

| Peer type | config/ | chains/               |
|-----------|---------|-----------------------|
| Owner     | sync    | git push/fetch+merge  |
| Other     | never   | freechains rules      |

Owner peers share the same key material.
Other peers require signature verification, reputation
checks, and size limits before accepting blocks.

## Diagram

```
       HOST A                         HOST B
    ┌──────────┐                   ┌──────────┐
    │ chains/  │── git clone ──>   │ chains/  │
    │ <hash>/  │                   │ <hash>/  │
    │          │<── fetch+merge ──  │          │
    │          │── fetch+merge ──> │          │
    └──────────┘                   └──────────┘
```
