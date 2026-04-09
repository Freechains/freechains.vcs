# Signing: Git vs Freechains

## CORRECTION: `gpgsig` IS inside the commit hash

Previous versions of this document claimed GPG signatures are
"outside the hash".
This is **wrong**.
The `gpgsig` header is part of the stored commit object and
**is included in the commit hash**.

### How git signing actually works

1. Git builds the commit content (tree, parent, author,
   committer, message) — call this the **payload**
2. Git signs the payload → produces a signature blob
3. Git injects the `gpgsig` header into the commit object
4. The commit hash (SHA-1) is computed over the **full object
   including `gpgsig`**
5. To verify, git strips `gpgsig`, recovers the payload, and
   checks the signature against it

### What the signature covers

| Field            | Signed | In hash |
|------------------|--------|---------|
| tree             | yes    | yes     |
| parent(s)        | yes    | yes     |
| author name      | yes    | yes     |
| author email     | yes    | yes     |
| author date      | yes    | yes     |
| committer name   | yes    | yes     |
| committer email  | yes    | yes     |
| committer date   | yes    | yes     |
| message          | yes    | yes     |
| extra headers    | yes    | yes     |
| gpgsig           | no (1) | yes     |

(1) The signature cannot cover itself — that would be circular.
The signature covers everything else.

### Consequences

| Property                           | Reality             |
|------------------------------------|---------------------|
| `gpgsig` in commit hash           | **YES**             |
| Stripping signature changes hash   | **YES**             |
| Signature covers content           | YES                 |
| Signature covers itself            | NO (circular)       |
| Different keys → different hashes  | YES (different sig) |

**Stripping a GPG signature changes the commit hash.**
The signed and unsigned versions are different objects with
different hashes.

### SHA-1 caveat

The signature covers the commit payload, not the raw bytes.
If SHA-1 collisions allow forging a different tree with the
same hash, the signature would still verify.
This is a weakness of git's data model, not of GPG signing
itself.

Source: [frank.sauerburger.io](https://frank.sauerburger.io/2018/11/07/security-of-git-commit-signatures.html)

## Comparison table (corrected)

|                          | Git                     | Freechains          |
|--------------------------|-------------------------|---------------------|
| Signing                  | Optional (GPG/SSH)      | Structural          |
| Key management           | External (`gpg`/`ssh`)  | Built-in            |
| Identity                 | Email + key, loose      | Public key = ID     |
| Unsigned content         | Fully valid             | Valid on `#` chains |
| Signature affects hash   | **yes** (via `gpgsig`)  | yes                 |
| Impersonation difficulty | Trivial (free text)     | Impossible          |

## Options for Freechains

### Option A: Standard GPG signing (reconsidered)

Use `git commit -S` with GPG keys.

**Pros:**
- Zero custom code — standard git tooling
- `git verify-commit` for validation
- `gpgsig` is inside the hash
- Stripping the sig changes the hash — tamper-evident

**Cons:**
- GPG is heavyweight (keyring, trust model)
- GPG signatures only contain key ID, not public key —
  verification requires signer's key in local keyring

**Note:** The register phase (see below) solves the keyring
problem — keys are registered in-chain, so every node builds
a local keyring from register commits.
GPG becomes viable again, though SSH remains simpler.

### Option B: Extra headers (abandoned)

Embed `freechains-pubkey` and `freechains-sig` as custom
headers in the commit object.

**Cons:**
- Requires raw commit object construction (can't use
  `git commit`)
- Fragile, complex, non-standard
- Breaks `git log`, `git verify-commit`, and other tooling

### Option C: Commit message (abandoned)

Embed pubkey and signature in the commit message body.

**Cons:**
- Ugly in `git log`
- Must parse message to extract crypto fields
- Mixes human-readable and machine data

### Option D: SSH signing (chosen)

Use `git commit -S` with `gpg.format=ssh`.

**Pros:**
- **Self-validating**: `gpgsig` header embeds the full
  public key — any node can verify without a keyring
- No GPG keyring management — no import/export needed
- Ed25519 — same curve as crypto.md's openssl choice
- Standard git tooling (`git verify-commit` with
  `allowed_signers`)
- Signature is inside the commit hash (same as GPG)
- `ssh-keygen` is ubiquitous, `gpg` is heavyweight

**Cons:**
- Requires Git >= 2.34 (released 2021-11)
- Verification needs a temporary `allowed_signers` file
  (built on the fly from the signature itself)
- `ssh-keygen` required for verify (standard on all systems)

## Decision: Option D — SSH signing

Option A (GPG) was the initial choice but has a critical flaw
for p2p: GPG signatures only contain the key ID, not the
public key.
Verification requires the signer's public key in the local
GPG keyring — impossible in a trustless p2p network where
peers are unknown.

Option D (SSH signing) solves this:
- Signature is inside the commit hash (same as GPG)
- Stripping it changes the hash (tamper-evident)
- Different signers produce different block hashes
- **Self-validating**: pubkey embedded in signature
- No key distribution needed — every commit carries its
  own verification material

## Why git's trust model works for Freechains

- The `gpgsig` header is part of the hash, so the block
  identity (commit hash) includes the signature
- A peer cannot strip or forge a signature without producing
  a different hash
- Replication can verify signatures on arrival using
  `git verify-commit`
- The only trust anchor needed is the SSH public key, which
  maps directly to Freechains' "public key = identity" model

The remaining difference: git's author/committer fields are
free text, so a signed commit proves "key X signed this" but
not "the author field is truthful".
For Freechains, the signing key **is** the identity — the
author/committer name/email are irrelevant metadata.

## Identity model

- Identity = key string (fingerprint for GPG, pubkey for SSH)
- `--sign <key-string>` on the CLI
- Internally: resolve key → private key path for signing
- Key string used in: `G.authors`, pioneers, `apply()`

### Pioneer format in `genesis-*.lua`

```lua
pioneers = {
    -- SSH: key is identity AND full material
    { name = "Alice", type = "ssh",
      key = "ssh-ed25519 AAAA..." },

    -- GPG: key is fingerprint, base64 is full pubkey blob
    { name = "Bob", type = "gpg",
      key    = "CA6391CEA51882DF980E0F0C6774E21538E4078B",
      base64 = "mDMEaavwGBYJKwYBBAHaRw8BAQdA..." },
}
```

| Field    | SSH                    | GPG                       |
|----------|------------------------|---------------------------|
| `name`   | human-readable label   | human-readable label      |
| `type`   | `"ssh"`                | `"gpg"`                   |
| `key`    | full pubkey (~80 ch)   | fingerprint (40 ch)       |
| `base64` | —                      | pubkey blob (~300 ch)     |

- `key` is always the identity (used in `G.authors`, `apply()`)
- Keyring build by `type`:
  - `gpg`: wrap `base64` with PGP armor headers → `.asc`
  - `ssh`: write `name .. " " .. key` → `allowed_signers`
- For GPG, `key` is derivable from `base64` (SHA-1 hash)
  but stored explicitly for fast lookup

## Register phase

### Concept

An **identity commit** is a special commit that modifies
keyring files inside the chain's `.freechains/` directory.
A trailer identifies it:

```
--trailer 'Freechains: identity'
```

This follows the existing trailer pattern (`post`, `like`,
`state`, `identity`).

The chain itself becomes its own PKI — the history of
identity commits is the ledger of trusted keys.

### Mechanics

- Identity commit adds a pubkey to the chain's keyring:
  `.freechains/keys/allowed_signers` (SSH) or imports into
  `.freechains/gpg/` (GPG)
- Revocation: an identity commit can also remove a key
- Identity commits must be signed by a pioneer or an
  already-registered key
- Replay reconstructs the keyring deterministically —
  every node that replays the chain builds the same keyring

### Bootstrap

Pioneers are known from genesis — they form the initial
keyring. A pioneer's first action can be an identity commit
for their own key. Subsequent keys are registered by
existing members.

### Consequences

| Property                    | Before identity  | After identity      |
|-----------------------------|------------------|---------------------|
| Key distribution            | Extract from sig | Built from chain    |
| Verification                | Parse sig blob   | `git verify-commit` |
| GPG support                 | Impossible (p2p) | Viable              |
| Revocation                  | Not supported    | Identity commit     |
| Keyring determinism         | N/A              | Yes (replay)        |
| SSH blob parsing needed     | Yes              | Only for bootstrap  |

## Git SSH signing mechanics

**Signing:**
```
git -c gpg.format=ssh \
    -c user.signingkey=/path/to/id_ed25519 \
    commit -S -m "msg"
```

**Open question:**
- `user.signingkey` accepts both a file path and a literal
  public key string (Git >= 2.35).
  Literal string is simpler (no temp files), but needs
  confirmation that it works for signing (not just verify).
  Must test before deciding.

## Verification flow (updated — identity phase)

### GPG (current, minimal change)

**At genesis (`chains.lua` → `pioneers()`):**
1. For each pioneer fingerprint, export pubkey:
   `gpg --export --armor <KEY> > .freechains/keys/<KEY>.asc`
2. Commit keyring files with
   `--trailer 'Freechains: identity'`
3. Then commit state as usual
   (`--trailer 'Freechains: state'`)

**At post/like (no change):**
- Signing uses user's `GNUPGHOME` as before
- `%GF` extracts fingerprint as before

**At sync (`sync.lua` → `replay()`):**
1. On `trailer == "identity"`: skip (keyring already in
   the repo tree, applied by merge)
2. For post/like verification: build ephemeral GNUPGHOME
   from `.freechains/keys/*.asc` files in the chain
3. `GNUPGHOME=<tmp> git verify-commit <hash>`
4. Pass `%GF` fingerprint to `apply()`

### SSH (future)

**Normal commits (post-registration):**
1. Keyring already built from identity commits
   (`allowed_signers` file exists in chain)
2. `git verify-commit <hash>` — git matches signature
   against `allowed_signers`
3. Pass verified pubkey to `apply()`

**Identity commits (bootstrap):**
1. Genesis pioneers are the initial keyring
2. An identity commit from a pioneer is verified against
   the genesis keyring
3. After verification, the new key is added to the keyring
4. Subsequent identity commits verified against the
   growing keyring

**No SSH blob parsing needed for normal operation.**
Parsing is only needed if we want to support a mode where
unregistered keys can post (e.g., `#` open chains).

## Implementation

### Done (GPG era — to be migrated)

- `src/freechains`: added `--sign <KEY_ID>` option to
  `chain <alias> post file|inline` commands
- When `--sign` is present, the git commit call adds
  `-c user.signingkey=<KEY_ID> -c gpg.format=openpgp -S`
- When absent, commit stays unsigned (current behavior)
- `tst/cli-sign.lua`: tests with ephemeral GPG Ed25519 key
    - signed post succeeds + returns valid hash
    - `git verify-commit` passes on signed block
    - `gpgsig` header present in commit object
    - unsigned post still works (regression)
    - unsigned commit has no `gpgsig` header
- Verification happens at merge time (pre-merge-commit hook),
  not as a separate command

### Pending (general)

- Key management (`freechains keys` command)
- Encryption (shared/sealed for private/personal chains)
- Pre-merge-commit hook for signature verification

### Phase 1: GPG identity commits (minimal, keep tests)

**Goal:** Chain carries its own GPG keyring. No changes to
signing or test infrastructure.

1. **Update `genesis-*.lua` — pioneer format**
   - Change from string to table:
     `{ name="test", type="gpg", key="CA6391...",
       base64="mDME..." }`
   - `base64` contains full GPG pubkey (from
     `gpg --export --armor`, body only, no PGP headers)
   - SSH pioneers have no `base64` (`key` is full material)

2. **Update `chains.lua` — `pioneers()` function**
   - Iterate `T.pioneers` as tables, not strings
   - `A[p.key] = { reps = n }` (identity = `p.key`)
   - Write keyring based on `p.type`:
     - `gpg`: wrap `p.base64` with PGP armor headers →
       `.freechains/keys/<key>.asc`
     - `ssh`: append `p.name .. " " .. p.key` to
       `.freechains/keys/allowed_signers`
   - Skel provides `.freechains/keys/` via `.gitkeep`

3. **Update `chains.lua` — chain creation**
   - `.freechains/keys/` already included in `git add .freechains/`
   - Genesis stays as single state commit (keyring files
     included alongside state files)

3. **Update `sync.lua` — `replay()` loop (line 69)**
   - Add `elseif trailer == "identity"` branch (skip/no-op,
     keyring files are already in the tree after merge)
   - Currently `assert(trailer == "state")` — add identity
     to the accepted set

4. **Update `sync.lua` — verification (future)**
   - Build ephemeral GNUPGHOME from chain's
     `.freechains/keys/*.asc` for `git verify-commit`
   - Not needed for current tests (GNUPGHOME already set)
   - Mark as TODO for p2p scenario

5. **Update `tst/cli-sign.lua`**
   - Add test: identity commit exists after `chains add`
   - Verify `.freechains/keys/<KEY>.asc` is in the repo
   - Verify trailer is `Freechains: identity`

**Files changed:** `chains.lua`, `sync.lua`
**Files added:** none
**Tests broken:** none (GNUPGHOME unchanged, signing unchanged)

### Phase 2: SSH migration (future)

1. Generate SSH test keys (`tst/ssh-keys/`)
2. Update `post.lua`: `gpg.format=ssh`, `user.signingkey=<path>`
3. Update `like.lua`: same
4. Update `tests.lua`: SSH keys, remove GNUPGHOME
5. Update genesis files: pubkey strings as pioneers
6. Update `sync.lua`: verify against `allowed_signers`
7. Identity commits write `allowed_signers` instead of `.asc`
