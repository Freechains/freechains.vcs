# Tests

## Goal

Port the Kotlin test suite (`freechains.kt/src/test/kotlin/Test.kt`) to shell scripts,
test-first, using only command-line tools (openssl, git) and eventually Lua.

## Constraints

- No Python, no age, no external dependencies beyond openssl + git + coreutils
- Data described as Lua literals (when Lua is available)
- Crypto via `openssl` (Ed25519 sign, X25519 key exchange, AES-256-CBC) — see [crypto.md](crypto.md) for alternatives
- Tests in `tst/`, one script per section, driven by `make`

## Done

### Infrastructure

- `tst/common.sh` — shell test helper (assert_eq, assert_neq, assert_ok, assert_fail, report)
- `tst/common.lua` — Lua test helper (same assertions + shell(), tmpwrite(), readfile(), writefile())
- `tst/fc-crypto.sh` — crypto wrapper (openssl only: keygen, pubkey, sign, verify, shared-key, shared-encrypt, shared-decrypt, seal-encrypt, seal-decrypt)
- `tst/Makefile` — `make a` runs shell tests, `make a-lua` runs Lua tests

### Section A — Primitives (4 tests x 2 languages, 60 assertions total)

Shell versions (30 assertions):

| File | Kotlin original | What it tests |
|---|---|---|
| `a1.sh` | `a1_json` | Lua literal + binary (0..255) + empty + 200KB round-trip through git blob |
| `a2.sh` | `a2_shared` | Symmetric encrypt/decrypt, deterministic key derivation, wrong-key rejection |
| `a3.sh` | `a3_pubpvt` | Asymmetric encrypt/decrypt (X25519+AES), Ed25519 sign/verify, wrong-key/tamper rejection |
| `a4.sh` | `a4_minus` | Sorted set difference with comm -23 (integers, hashes, identity/empty cases) |

Lua versions (30 assertions):

| File | What it tests |
|---|---|
| `a1.lua` | Same as a1.sh — git blob round-trip via Lua io/os |
| `a2.lua` | Same as a2.sh — calls fc-crypto.sh via shell() |
| `a3.lua` | Same as a3.sh — calls fc-crypto.sh via shell() |
| `a4.lua` | Same as a4.sh — pure Lua sorted set difference (no comm) |

### Section B — Host & Chain Init (3 tests, 65 assertions)

Shell versions:

| File | Kotlin original | What it tests |
|---|---|---|
| `b1.sh` | `b1_host` | Host dir layout (chains/ + keys/), chain join (bare repo + symlink), naming (#topic, @pubkey, $private), duplicate join rejection, chains list, chain leave, invalid path rejection |
| `b2.sh` | `b2_chain` | Genesis block creation (blob→tree→commit), payload round-trip, parent links, git log ordering, reload persistence, extra headers (freechains-pubkey/sig), empty-tree commit (like/dislike), binary payload (0..255) |
| `b3.sh` | *(new)* | Directory replication: host_init creates config/ (git repo) + chains/, config tracks files, owner-to-owner clone/pull of config, owner-to-owner clone/push of chains, non-owner gets chains only (no config), bidirectional chain sync, config history preservation |

### Genesis Block (1 test, 26 assertions)

| File | What it tests |
|---|---|
| `x1.sh` | Deterministic genesis commit: canonical Lua-style serialization of (version, type) as commit message, zeroed author/date fields, empty tree, determinism (same params → same hash), uniqueness (different params → different hash), user field exclusion, all chain types (public/private/personal), pioneer canonicalization, writeable flag, cross-peer identity matching |

## TODO

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

---

# Test Catalog

Source: `freechains.kt/src/test/kotlin/Test.kt` — 2552 lines, 58 tests (52 active, 6 disabled)

## Section A — Primitives

| Kotlin test | Shell | Lua | What it verifies |
|---|---|---|---|
| `a1_json` | `a1.sh` | `a1.lua` | Data round-trip through git blob (Lua literal, binary 0..255, empty, 200KB) |
| `a2_shared` | `a2.sh` | `a2.lua` | Symmetric encrypt/decrypt (AES-256-CBC), key derivation, wrong-key rejection |
| `a3_pubpvt` | `a3.sh` | `a3.lua` | Asymmetric encrypt/decrypt (X25519+AES), Ed25519 sign/verify, wrong-key/tamper |
| `a4_minus` | `a4.sh` | `a4.lua` | Sorted set difference (comm -23 in shell, pure Lua in .lua) |

## Section B — Host & Chain Initialization

| Test | What it verifies |
|---|---|
| `b1_host` | `Host_load` succeeds for valid dir, throws `Permission denied` for `/` |
| `b2_chain` | Join a chain, reload it, create a block, verify block persistence |

## Section C — Consensus, Ordering & Reputation

| Test | What it verifies |
|---|---|
| `c1_post` | Post blocks on identity chain (`@pub`), block existence, payload size limits |
| `c02_blocked` | Blocks from non-pioneer authors stay in `BLOCKED` heads |
| `c03_all` | Walk all blocks from heads, verify pioneer reputation stays at 30 |
| `c04_all` | Reputation stability across multiple time-advancing consensus rounds |
| `c05_seq` | Sequential DAG with a like — consensus order, reputation transfer over time |
| `c06_ord1` | Complex DAG with forks/merges from 3 authors — ordering with concurrent branches |
| `c07_ord2` | Variation of c06 — different fork/merge pattern, verify consensus string |
| `c08_ord3` | 3-way concurrent branches with different like weights |
| `c09_ord4` | 3-way fork merged into single commit, verify ordering |
| `c10_inv1` | Simple linear chain — consensus order matches insertion order |
| `c11_inv2` | Dislike causes reputation drop; posts beyond rep limit become invisible in consensus |
| `c12_dt12h` | 12-hour delay rule: reputation only materializes after 12h window |
| `c13_pioneers` | Multiple pioneers split initial reputation equally (15+15=30) |
| `c14_100s` | *(Disabled)* Stress test: 500 like+post pairs with `check_reset` |
| `c15` | *(Disabled)* Load existing chain, verify heads consistency |
| `c16` | *(Disabled)* Load and print chain consensus |

## Section D — Protocol / Daemon

| Test | What it verifies |
|---|---|
| `d1_proto` | Full daemon lifecycle: start src+dst hosts, post blocks, `ping`, `chains`, `send`, `stop` |

## Section F — Peer Sync

| Test | What it verifies |
|---|---|
| `f1_peers` | Two hosts with independent blocks, `recv` merges blocks from remote into local |

## Section G — Size Limits

| Test | What it verifies |
|---|---|
| `g01_128` | 128KB payload limit: signed post OK at limit, fails above; identity chain owner exempt; private chain exempt |

## Section M — CLI Integration & Features

| Test | What it verifies |
|---|---|
| `m00_chains` | Host start, `chains list`, `chains join`, `chains leave` |
| `m01_args` | CLI argument parsing, `--help`, `genesis`, `heads`, `get block`, `post file` |
| `m01_blocked` | Posts from non-pioneer author — heads not split |
| `m01_trav` | `consensus` command returns blocks in correct order |
| `m01_listen` | Socket-based `chain listen` and `chains listen` — real-time notifications |
| `m02_crypto` | LazySodium keypair generation, `keys shared`, `keys pubpvt`, secret box encrypt/decrypt |
| `m02_crypto_passphrase` | Different passphrases produce different shared and pubpvt keys |
| `m02_crypto_pubpvt` | Ed25519->Curve25519 key conversion, sealed box encrypt/decrypt |
| `m03_crypto_post` | Post to private (`$sym`) and identity (`@pub`) chains with encryption |
| `m04_crypto_encrypt` | Encrypted payload: decrypted reads match, raw reads differ |
| `m05_crypto_encrypt_sym` | Symmetric encryption: post, send to peer, verify transfer |
| `m06_crypto_encrypt_asy` | Asymmetric encryption: post+encrypt, decrypt with pvt key, send to peer, verify |
| `m06x_crypto_encrypt_asy` | Owner-only chain (`@!pub`): only owner can post, encryption works |
| `m06y_shared` | Private shared chain (`$xxx`): wrong key rejects sync, correct key decrypts |
| `m07_genesis_fork` | Two hosts diverge from genesis, sync, verify independent reps |
| `m08_likes` | Like workflow via CLI: like twice, check reps accumulate |
| `m09_likes` | Full like/dislike lifecycle: likes, dislikes, peer sync, reputation accounting, blocked heads, self-like rejection |
| `m10_cons` | Consensus ordering across two peers with blocked posts |
| `m11_send_after_tine` | Send after like — internal assertion stress test |
| `m12_state` | Block state management: linked vs blocked heads, likes promoting blocks, dislikes rejecting blocks across peers |
| `m13_reps` | Reputation evolution over time: posting costs 1 rep, time regrants rep |
| `m13_reps_pioneers` | 3 pioneers each get 10 reps (30/3) |
| `m14_remove` | Dislike workflow: dislike doesn't remove already-liked content |
| `m15_rejected` | Cross-peer rejection: dislike on H0 causes block rejection, H1 posts independently, sync merges |
| `m16_likes_fronts` | Dislike after like: post stays accepted because prior like protects it |
| `m17_likes_day` | Dislike after 24h: too late to reject, post stays accepted |
| `m19_remove` | Self-dislike: author dislikes own post, payload becomes empty, reps drop to 0 |
| `m20_posts_20` | Post 23 blocks sequentially, verify head height |

## Section N — Merge & Consensus Convergence

| Test | What it verifies |
|---|---|
| `n01_merge_tie` | Two peers post concurrently, sync — consensus agrees (tiebreak by hash) |
| `n02_merge_win` | Concurrent posts with different reputation — higher-rep branch wins ordering |
| `n03_merge_ok` | 6 concurrent posts per peer, sync — consensus converges identically |
| `n04_merge_fail` | 101 concurrent posts per peer — consensus intentionally diverges (too many conflicts) |
| `n05_merge_fail` | Time-separated concurrent posts (8 days apart) — consensus diverges |
| `n05_merge_ok` | 3 pioneers, concurrent posts — consensus converges with enough reputation spread |
| `n06_merge_ok` | 12 rounds of concurrent posts with time advancement — consensus converges each round |
| `n07_merge_fail` | Same as n06 but 11 concurrent posts in final round — tests convergence boundary |
| `n08_merge_fail` | Mutual dislikes: peer A dislikes B's post, peer B dislikes A's — verify state after cross-sync |
| `n09_merge_fail_12h` | 12h reputation transfer exploit: branch steals rep, causing blocks to lose consensus visibility |

## Section X — Stress & Scale

| Test | What it verifies |
|---|---|
| `x01_sends` | Send 100 blocks from owner-only chain to peer — verify all 100 transfer |
| `x02_cons` | *(Disabled)* 1000 posts to a single chain — performance test |
| `x03_cons` | *(Disabled)* 9-node network, 5000 rounds of random posts+syncs — consensus convergence at scale |
| `x04_cons` | *(Disabled)* Load and print consensus from x03 data |

## Totals

| Section | Active | Disabled | Description |
|---|---|---|---|
| A | 4 | 0 | Primitives |
| B | 2 | 0 | Host & chain init |
| C | 13 | 3 | Consensus, ordering, reputation |
| D | 1 | 0 | Daemon protocol |
| F | 1 | 0 | Peer sync |
| G | 1 | 0 | Size limits |
| M | 20 | 0 | CLI integration |
| N | 9 | 0 | Merge convergence |
| X | 1 | 3 | Stress tests |
| **Total** | **52** | **6** | |
