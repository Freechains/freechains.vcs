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
| `sign` | `ARGS.sign` (CLI)         | `git log %GK`           | unsafe     |
| `time` | `NOW.s` (`os.time()`)     | `tonumber(git log %at)` | unsafe     |
| `beg`  | `ARGS.beg` (CLI flag)     | derived: `key == nil`   | safe       |

## Like Fields (`T.kind == 'like'`)

| Field    | Local source                | Replay source          | Status     |
|----------|-----------------------------|------------------------|------------|
| `kind`   | hardcoded `'like'`          | (TODO — not impl.)     | safe       |
| `sign`   | `ARGS.sign` (CLI)           | commit `%GK`           | unsafe     |
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

- **Signing** (post.lua): uses `-S` with
  `-c user.signingkey=KEY`
- **Reading** (sync.lua:43): `git log --format='%GK'`
  extracts fingerprint
- **Verifying**: nowhere — `%G?` is never checked

### The gap

`%GK` returns a fingerprint even if the signature is
invalid.
Git's `%G?` field gives the actual verification status:

| `%G?` | Meaning                            |
|-------|------------------------------------|
| `G`   | good (valid + trusted key)         |
| `U`   | good (valid + untrusted key)       |
| `B`   | bad signature                      |
| `N`   | no signature                       |
| `E`   | can't check (missing key)          |

### Attack: hand-crafted commits

A malicious remote can craft git commit objects with
arbitrary signature data (`git hash-object -t commit -w`).
Without checking `%G?`, `%GK` may return a fingerprint
from a forged or invalid signature.

### What's needed

In replay, read `%G?` alongside `%GK`.
Reject if `%G?` is not `G` or `U`.

Checking whether the key is "authorized" (exists in
`G.authors`) is NOT needed separately — `apply` already
handles it: unknown keys have no entry in `G.authors`,
so `reps = 0` → `reps <= 0` → "insufficient reputation".
Begs are never replayed.

## Proposed Checks

```
T.time:   type(T.time) == "number" and T.time >= 0
T.sign:   %G? must be G or U (signature valid)
          format: 40 hex chars (GPG fingerprint)
T.num:    type == "number" and num ~= 0
          and math.type(num) == "integer"
T.id:     for target == "author": author must exist
          in G.authors (no creation from likes)
T.hash:   #T.hash == 40 (defensive, low priority)
```

## Status

- [ ] Decide which checks go in apply vs caller
- [ ] Implement T.time validation
- [ ] Implement T.sign: check %G? in replay
- [ ] Implement T.num negative/fractional check
- [ ] Implement T.id author-existence check
- [ ] Add tests for malformed T fields
