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

| File                              | Location             | Shared | Mutable | Notes                                      |
|-----------------------------------|----------------------|--------|---------|---------------------------------------------|
| `config/keys/<pub>.pub`           | root/                | local  | immut   | Public key                                  |
| `config/keys/<pub>.key`           | root/                | local  | immut   | Encrypted private key                       |
| `peers.lua`                       | root/                | shared | mutable | Known peers, reps, chain lists              |
| `config.lua`                      | repo/.freechains/    | shared | immut   | Chain rules (type, time, reps, like)        |
| `authors.lua`                     | repo/.freechains/    | shared | mutable | Author → reputation mapping                 |
| `posts.lua`                       | repo/.freechains/    | shared | mutable | Post → like/dislike counts                  |
| `likes/like-*.lua`                | repo/.freechains/    | shared | immut   | Individual like/dislike payloads            |
| `random`                          | repo/.freechains/    | shared | immut   | Chain identity seed                         |
| user content (posts, PDFs, etc.)  | repo/                | shared | mutable | Application data, changes across commits    |
| `local/now.lua`                   | repo/.freechains/    | local  | mutable | Last staged timestamp (untracked)           |

## Shared vs Local

- **Shared**: replicated between peers via git
  (fetch/push/clone).
- **Local**: never leaves the host.
  Excluded from git tracking (`.git/info/exclude` or
  `.gitignore`).

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
