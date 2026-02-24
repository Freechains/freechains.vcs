# Freechains + Git: Design Overview

## Data Structure Relationships

- **Append-only logs** are the primitive — never overwrite, only grow
- **Immutability** enables content addressing: a value's hash becomes its identity
- **Merkle Trees** apply content addressing recursively — the root hash fingerprints the entire structure, enabling O(log n) proofs and efficient diffing
- **Blockchains** are a Merkle hash chain + append-only log + distributed consensus
- **CRDTs** solve a different problem: merging concurrent writes without coordination, often implemented on top of append-only op logs

All of them share the same root insight: **trust through structure, not through authority**.

---

## Database Options Considered

| Goal | Best Option |
|---|---|
| Append-only log + queryability | PostgreSQL (event sourcing) |
| High-throughput log | Kafka |
| Content-addressed blobs | IPFS or hash-keyed SQLite |
| Distributed sync without coordination | ElectricSQL / Ditto |
| Embedded, zero infrastructure | SQLite |

---

## Architecture Summary

Each section below has its own detailed plan file.

### Git as the Database — [git.md](git.md)

Chain = Repository (not branch). Each chain is its own bare git repo. Data model: block = commit, payload = blob, fork/merge = merge commit. Consensus via `git log --date-order`. Merge after every sync (single HEAD model). Sync-only merge commits marked with `freechains-sync: true` extra header.

### Chains — [chains.md](chains.md)

Chain = topic in pub-sub. Identified by genesis hash (`HASH(version, type)`). Three types: public (N↔N, reputation-based), private (encrypted, shared key), personal (1→N broadcast). Peers sync by genesis hash, not name. Local index maps human-readable aliases (`#`, `$`, `@`) to hashes.

### Command Mapping — [commands.md](commands.md)

Full mapping of all `freechains` CLI commands to git equivalents. Match scores from 1 (no equivalent) to 5 (perfect). Git hooks (`post-receive`, `pre-receive`, `post-merge`, `post-commit`) for the block acceptance pipeline.

### Signing — [signing.md](signing.md)

Git signing is outside the hash (fragile for trustless systems). Freechains embeds signature inside the hash via extra headers (`freechains-pubkey`, `freechains-sig`). Public key **is** the identity.

### Network — [network.md](network.md)

Radicle validates the architecture but is the wrong tool (wrong domain, no Lua, no reputation). GitHub/GitLab useful as bootstrap/seed relay for NAT traversal. Self-hosted GitLab closest to a full Freechains seed node.

### SQLite — [sqlite.md](sqlite.md)

Companion store for computed state: consensus cache and reputation checkpoints. Write-through cache — deletable and rebuildable from git history. Git is always the source of truth.

### Filesystem Layout — [layout.md](layout.md)

XDG-compliant per-user layout. Bare git repos in `~/.local/share/freechains/chains/`. Symlinks for human-readable chain names (`@pubkey`, `#topic`, `$private`). SQLite `.db` files adjacent to their repos.

### Crypto — [crypto.md](crypto.md)

Current: openssl CLI (Ed25519 + X25519 + AES-256-CBC). Next: luasodium (NaCl API, matches Kotlin original). Full comparison of 7 alternatives.

### Tests — [tests.md](tests.md)

Porting Kotlin test suite (58 tests) to shell + Lua. Section A done (4 tests x 2 languages, 60 assertions). Sections B-X pending.

---

## Lua Libraries

| Purpose | Library | Notes |
|---|---|---|
| Git (official) | [libgit2/luagit2](https://github.com/libgit2/luagit2) | Full libgit2 API, requires C compilation |
| Git (LuaJIT FFI) | [luapower/libgit2](https://github.com/luapower/libgit2) | No compilation, pure FFI |
| SQLite | [lsqlite3](https://luarocks.org/modules/dougcurrie/lsqlite3) | Standard binding |
| SQLite (bundled) | lsqlite3complete | Bundles SQLite amalgamation — zero external deps |
| Crypto (libsodium) | [luasodium](https://github.com/luasodium/luasodium) | Key generation replacing `freechains keys` |
| Freechains Lua client | [Freechains/lua](https://github.com/Freechains/lua) | Official Lua repo |
| Freechains Lua wrapper | [micahkendall/freechains-lua](https://github.com/micahkendall/freechains-lua) | OOP wrapper over CLI |
