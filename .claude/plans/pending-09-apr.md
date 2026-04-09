# Pending — 2026-04-09

Snapshot of in-progress work and side items.
Main plan: [ident.md](ident.md).

## ident.md steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `ident.lua` | done |
| 2 | `apply()` `'ident'` kind in common.lua | done |
| 3 | `like author <KEY>` merges ident branch (initial) | done |
| 4 | **Uniform model** (sub-items below) | in progress |
| 4a | Ident ref by HASH (not KEY) | pending |
| 4b | New like target `ident`, id=hash | pending |
| 4c | apply: `kind=ident` creates `G.posts[hash]` blocked; `kind=like target=ident` validates + transfers + unblocks | pending |
| 4d | Share scaffolding in like.lua (beg & ident → same merge path) | pending |
| 4e | Update tests: rename `like-author-*` → `like-ident-*`, use HASH | pending |
| 4f | Update plan to reflect uniform model | pending |
| 5 | `post.lua`: post on ident branch when reps <= 0 | pending |
| 6 | Remove `--beg` flag from post + parser | pending |
| 7 | `sync.lua`: handle `ident` trailer + git-native fallback | pending |
| 8 | Rewrite beg tests as ident tests | pending |
| 9 | Plan updates as we go | ongoing |

## Side items

| # | Item | Status |
|---|------|--------|
| A | Merge abort on apply failure + tests (beg & ident, insufficient reps) | pending |
| B | Decision: drop or keep "already registered" off-main check after HASH refs | pending |
| C | Refactor to `G.commits` model (every entity is a commit) | deferred |
| D | SSH per-key `.pub` files + on-the-fly `allowed_signers` assembly | deferred |
| E | Pre-merge-commit hook for sig verification | deferred |
| F | `freechains keys` command | deferred |
| G | Encryption (shared/sealed for private chains) | deferred |
