# Session Plan: Implement Tests

## Goal

Port the Kotlin test suite (`freechains.kt/src/test/kotlin/Test.kt`) to shell scripts,
test-first, using only command-line tools (openssl, git) and eventually Lua.

Full test catalog: see `tests.md`.

## Constraints

- No Python, no age, no external dependencies beyond openssl + git + coreutils
- Data described as Lua literals (when Lua is available)
- Crypto via `openssl` (Ed25519 sign, X25519 key exchange, AES-256-CBC)
- Tests in `tst/`, one script per section, driven by `make`

## Done

### Infrastructure

- `tst/common.sh` — test helper (assert_eq, assert_neq, assert_ok, assert_fail, report)
- `tst/fc-crypto.sh` — crypto wrapper (openssl only: keygen, pubkey, sign, verify, shared-key, shared-encrypt, shared-decrypt, seal-encrypt, seal-decrypt)
- `tst/Makefile` — `make a` runs all Section A tests

### Section A — Primitives (4 tests, 30 assertions)

| File | Kotlin original | What it tests |
|---|---|---|
| `a1.sh` | `a1_json` | Lua literal + binary (0..255) + empty + 200KB round-trip through git blob |
| `a2.sh` | `a2_shared` | Symmetric encrypt/decrypt, deterministic key derivation, wrong-key rejection |
| `a3.sh` | `a3_pubpvt` | Asymmetric encrypt/decrypt (X25519+AES), Ed25519 sign/verify, wrong-key/tamper rejection |
| `a4.sh` | `a4_minus` | Sorted set difference with comm -23 (integers, hashes, identity/empty cases) |

## TODO

### Section B — Host & Chain Init

- `b1.sh` — init a bare git repo as a chain, reject invalid paths
- `b2.sh` — join a chain, reload it, create a commit (block), verify persistence

### Section C — Consensus, Ordering & Reputation

- Requires: consensus algorithm in Lua or shell
- `c01.sh` through `c13.sh` — DAG construction, head management, reputation math, ordering

### Section D — Protocol / Daemon

- Requires: git daemon wrapper
- `d1.sh` — start/stop hosts, ping, chain listing, send blocks

### Section F — Peer Sync

- Requires: git push/fetch wrappers
- `f1.sh` — two repos, fetch merges blocks

### Section G — Size Limits

- `g01.sh` — payload size enforcement (128KB)

### Section M — CLI Integration

- Requires: CLI tool (Lua or shell)
- 20 tests covering chains join/leave/list, posting, likes/dislikes, crypto, peer sync

### Section N — Merge & Consensus Convergence

- Requires: full consensus + reputation implementation
- 9 tests for multi-peer merge scenarios (tie, win, ok, fail)

### Section X — Stress & Scale

- `x01.sh` — 100-block bulk send
