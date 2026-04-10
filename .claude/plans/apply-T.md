# apply(G, T) — Field Validation

## Context

`apply` receives a `T` table from two sources:
- **Local** (post.lua): user-controlled CLI args
- **Replay** (sync.lua): remote-controlled git data

Remote data is untrusted.
All `T` fields must be validated before use.

## Post Fields (`T.kind == 'post'`)

| Field  | Local source              | Replay source           | Status     |
|--------|---------------------------|-------------------------|------------|
| `kind` | hardcoded `'post'`        | hardcoded `'post'`      | safe       |
| `hash` | `git rev-parse HEAD`      | `git log %H`            | safe       |
| `sign` | `ssh.pubkey(REPO, hash)`  | `ssh.pubkey(REPO, hash)`| unsafe     |
| `time` | `NOW.s` (`os.time()`)     | `tonumber(git log %at)` | unsafe     |
| `beg`  | `ARGS.beg` (CLI flag)     | derived: `key == nil`   | safe       |

## Like Fields (`T.kind == 'like'`)

| Field    | Local source                | Replay source          | Status     |
|----------|-----------------------------|------------------------|------------|
| `kind`   | hardcoded `'like'`          | (TODO — not impl.)     | safe       |
| `sign`   | `ssh.pubkey(REPO, hash)`    | `ssh.pubkey(REPO, hash)`| unsafe    |
| `time`   | `NOW.s`                     | commit `%at`           | unsafe     |
| `num`    | `ARGS.number * C.reps.unit` | like payload file      | unsafe     |
| `target` | `ARGS.target` (CLI)         | like payload file      | validated  |
| `id`     | `ARGS.id` (CLI)             | like payload file      | unsafe     |
| `beg`    | computed locally            | derived                | safe       |

## Current Validation in apply

Checks that exist:
- `T.sign` nil for likes → "unsigned"
- `T.num == 0` → "expected positive integer"
- `T.target` not "post"/"author" → "target must be..."
- `T.target == "post"` and `G.posts[T.id]` nil →
  "post not found"
- `reps <= 0` for signed posts and likes

## Missing Validation

### T.time

Used directly in time_effects (discount + consolidation
scans).
No checks at all.

Dangerous values:
- `nil` — `tonumber` on malformed `%at` returns nil,
  `time > G.now` crashes
- negative — breaks time comparisons
- huge — consolidation scan grants reps to all pending
  posts at once
- non-integer — unexpected behavior in time arithmetic

### T.sign

Used as table key in `G.authors[T.sign]`.
No format check.

Dangerous values:
- arbitrary string — remote signs with unknown key,
  gets inserted into `G.authors` as a new entry
- empty string — different from nil, bypasses nil checks

### T.num

Only checks `== 0`.

Dangerous values:
- negative — bypasses `num == 0` check, inverts the
  like direction (gives reps instead of taking)
- fractional — unexpected behavior in integer arithmetic
- huge — drains or inflates reps beyond intended limits

### T.id (for target == "author")

Used as key with no existence check.
Line 131-132 creates `G.authors[T.id]` if absent.

Dangerous values:
- arbitrary string — creates fake author entries in
  `G.authors` with `reps = 0 + num`

### T.hash

Used as table key in `G.posts[T.hash]`.
Safe from git (always 40 hex chars from `%H`), but
never explicitly checked.

## Signature Verification

### Current state

- **Signing** (post.lua, like.lua): uses `-S` with
  `-c user.signingkey=KEY -c gpg.format=ssh`
- **Reading** (post.lua, like.lua, sync.lua):
  `ssh.pubkey(REPO, hash)` extracts the SSH pubkey
  from the SSHSIG blob embedded in the `gpgsig` header
- **Verifying**: `ssh.verify(REPO, hash)` writes a
  temporary `allowed_signers` file and calls
  `git verify-commit`

### How ssh.pubkey works

`ssh.pubkey(repo, hash)` parses the SSHSIG binary
format directly in Lua (base64 decode via shell, then
byte-level parsing). Returns the SSH pubkey string
(`ssh-ed25519 AAAA...`) or nil if unsigned.
No `ssh-keygen` needed for extraction.

### How ssh.verify works

`ssh.verify(repo, hash)` calls `ssh.pubkey` first,
then writes `"git <pubkey>\n"` to
`.freechains/tmp/allowed_signers`, runs
`git verify-commit`, and cleans up.
Returns the pubkey on success, nil on failure.

### Attack: hand-crafted commits

A malicious remote can craft git commit objects with
arbitrary signature data (`git hash-object -t commit -w`).
`ssh.pubkey` extracts whatever pubkey is in the blob
without verifying the signature.
`ssh.verify` catches this — it runs `git verify-commit`
which checks the signature against the extracted key.

### Current gap

Replay (`sync.lua`) calls `ssh.pubkey` but not
`ssh.verify` per commit. Verification during replay
is deferred as an optimization question (see
signing.md).

Checking whether the key is "authorized" (exists in
`G.authors`) is NOT needed separately — `apply` already
handles it: unknown keys have no entry in `G.authors`,
so `reps = 0` → `reps <= 0` → "insufficient reputation".
Begs are never replayed.

## Proposed Checks

```
T.time:   type(T.time) == "number" and T.time >= 0
          monotonic: T.time >= parent's timestamp
          (move check from post.lua:66-76 into apply)
T.sign:   ssh.verify() must succeed (signature valid)
          format: "ssh-ed25519 <base64>" (SSH pubkey)
T.num:    type == "number" and num ~= 0
          and math.type(num) == "integer"
T.id:     for target == "author": author must exist
          in G.authors (no creation from likes)
T.hash:   #T.hash == 40 (defensive, low priority)
```

## Beg Replay

Begs come in pairs during replay:
1. An unsigned post (beg) — `trailer == "post"`, no key
2. A like targeting that beg — `trailer == "like"`

Currently replay skips likes (`error "TODO"`), so begs
are never unblocked during replay.

**Decision:** Add a `"Freechains: beg"` trailer to beg
commits so replay can distinguish begs from regular
unsigned posts without relying on `key == nil` heuristic.

## Status

- [x] Decide which checks go in apply vs caller
  - Refactored apply signature to `(G, kind, time, T)`
  - Split apply body by kind (post/like/reps)
- [x] Implement T.time validation
  - Monotonic check moved from post.lua into apply
  - `G.now` tracks highest seen timestamp (max)
  - Sync resets `G.now` between winner/loser replay
- [ ] Implement T.sign: check %G? in replay
- [ ] Implement T.num negative/fractional check
- [ ] Implement T.id author-existence check
- [ ] Add tests for malformed T fields
- [ ] Implement like replay in sync.lua
  - replay must read like payload from commit
  - replay must handle beg+like pairs
- [ ] Add "Freechains: beg" trailer to beg commits
- [ ] Fix sync replay error handling
  - replay now returns false on apply failure
  - all callers check and abort with ERROR
  - current bug: step 1 (basic recv) fails with
    "insufficient reputation" — need to debug
    checkpoint state (pioneer reps not loaded?)
