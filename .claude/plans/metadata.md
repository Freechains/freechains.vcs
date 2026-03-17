# Metadata: Data Files Catalog

## Overview

All persistent data in Freechains, categorized by location,
mutability, and replication scope.

Commits are always immutable in git.
Files inside commits may be mutable across commits (i.e.,
their content changes from one commit to the next).

## Locations

| Prefix             | Meaning                                  |
|--------------------|------------------------------------------|
| `root/`            | Host directory (top-level)               |
| `repo/`            | Chain repo (`chains/<hash>/`)            |
| `repo/.freechains/`| Chain metadata inside repo               |

## Data Files

| File                              | Location             | Scope   | Mutable | Notes                                       |
|-----------------------------------|----------------------|---------|---------|-----------------------------------------------|
| `config/keys/<pub>.pub`           | root/                | local   | immut   | Public key                                    |
| `config/keys/<pub>.key`           | root/                | local   | immut   | Encrypted private key                         |
| `peers.lua`                       | root/                | shared  | mutable | Known peers, reps, chain lists                |
| `config.lua`                      | repo/.freechains/    | genesis | immut   | Chain rules (type, time, reps, like)          |
| `random`                          | repo/.freechains/    | genesis | immut   | Chain identity seed                           |
| `likes/like-*.lua`                | repo/.freechains/    | shared  | immut   | Individual like/dislike payloads              |
| user content (posts, PDFs, etc.)  | repo/                | shared  | mutable | Application data, changes across commits      |
| `authors.lua`                     | repo/.freechains/    | local   | mutable | Author → reputation mapping (from DAG)        |
| `posts.lua`                       | repo/.freechains/    | local   | mutable | Post → like/dislike counts (from DAG)         |
| `local/now.lua`                   | repo/.freechains/    | local   | mutable | Last staged timestamp (untracked)             |

## Scope: Shared vs Genesis vs Local

- **Shared**: replicated between peers via git
  (fetch/push/clone).
  Committed in every relevant commit.
- **Genesis**: committed only in the genesis commit.
  Extracted locally on clone/fetch, never recommitted.
  Untracked after extraction (`.git/info/exclude`).
- **Local**: never leaves the host.
  Reconstructed from DAG or created locally.
  Excluded from git tracking (`.git/info/exclude`).

## Mutable vs Immutable

- **Immutable**: set once (at genesis or creation), never
  changes. Validation rejects any commit that alters it.
- **Mutable**: updated across commits as chain state evolves
  (reputation, posts, content).

## Key References

| Topic          | Plan                                 |
|----------------|--------------------------------------|
| config.lua     | [genesis.md](genesis.md)             |
| authors, posts | [reps.md](reps.md)                   |
| peers.lua      | [peers.md](peers.md)                 |
| now.lua        | [local-staging.md](local-staging.md) |
| layout         | [layout.md](layout.md)               |
| immutability   | [consensus.md](consensus.md)         |
