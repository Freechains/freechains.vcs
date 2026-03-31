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
| Key management           | External (`gpg`)        | Built-in or GPG     |
| Identity                 | Email + key, loose      | Public key = ID     |
| Unsigned content         | Fully valid             | Valid on `#` chains |
| Signature affects hash   | **yes** (via `gpgsig`)  | yes                 |
| Impersonation difficulty | Trivial (free text)     | Impossible          |

## Options for Freechains

### Option A: Standard GPG signing (recommended)

Use `git commit -S` with GPG keys.

**Pros:**
- Zero custom code — standard git tooling
- `git verify-commit` for validation
- `gpgsig` is inside the hash — block identity includes
  authorship proof
- Stripping the sig changes the hash — tamper-evident
- GitHub/GitLab show "Verified" badges
- Different authors signing same content → different hashes
  (desirable: different blocks)

**Cons:**
- Requires GPG key management on each peer
- GPG is heavyweight (keyring, trust model)
- Author/committer fields are still free text (but the sig
  binds them to a key)

**Flow:**
```
git commit -S -c user.signingkey=<KEY_ID> ...
```

**Verification:**
```
git verify-commit <hash>
```

**Key storage:**
Keys live in `<host>/config/keys/` as GPG exports, imported
into the local keyring on use.

### Option B: Extra headers (original plan, abandoned)

Embed `freechains-pubkey` and `freechains-sig` as custom
headers in the commit object.

**Pros:**
- Inside the hash (same as GPG)
- No GPG dependency
- Pubkey explicitly visible in commit headers

**Cons:**
- Requires raw commit object construction (can't use
  `git commit`)
- Must build the commit bytes manually, sign, rebuild
  with signature, then write via `git hash-object -t commit`
- Fragile, complex, non-standard
- Breaks `git log`, `git verify-commit`, and other tooling

### Option C: Commit message (fallback)

Embed pubkey and signature in the commit message body.

**Pros:**
- Inside the hash
- Easy to implement (`-m` flag)
- No raw object construction

**Cons:**
- Ugly in `git log`
- Must parse message to extract crypto fields
- Mixes human-readable and machine data

## Decision: Option A — GPG signing

Standard GPG signing satisfies all Freechains requirements:
- Signature is inside the commit hash
- Stripping it changes the hash (tamper-evident)
- Different signers produce different block hashes
- Standard tooling works out of the box

## Why git's trust model works for Freechains

Previously this document argued git's model was fragile for
trustless systems.
With the corrected understanding:

- The `gpgsig` header is part of the hash, so the block
  identity (commit hash) includes the signature
- A peer cannot strip or forge a signature without producing
  a different hash
- Replication can verify signatures on arrival using
  `git verify-commit`
- The only trust anchor needed is the GPG public key, which
  maps directly to Freechains' "public key = identity" model

The remaining difference: git's author/committer fields are
free text, so a signed commit proves "key X signed this" but
not "the author field is truthful".
For Freechains, the signing key **is** the identity — the
author/committer name/email are irrelevant metadata.

## Implementation

### Done

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

### Pending

- Key management (`freechains keys` command)
- Encryption (shared/sealed for private/personal chains)
- Pre-merge-commit hook for signature verification

## Pending — SSH migration

**Goal:** Replace GPG signing with SSH signing (Ed25519).
Git natively supports `gpg.format=ssh` since v2.34.

**Why SSH over GPG:**
- No keyring management (just files)
- Ed25519 keys are simple files, no `GNUPGHOME`
- `ssh-keygen` is ubiquitous, `gpg` is heavyweight
- Aligns with crypto.md — Ed25519 everywhere

### Identity model

- Identity = SSH public key string (`ssh-ed25519 AAAA...`)
- `--sign <path-to-private-key>` on the CLI
- Internally: `ssh-keygen -y -f <path>` → pubkey string
- Pubkey string used in: `G.authors`, pioneers, `apply()`
- Pioneer lists in `genesis-*.lua` become pubkey strings

### Git SSH signing mechanics

**Signing (always needs private key file path):**
```
git -c gpg.format=ssh \
    -c user.signingkey=/path/to/id_ed25519 \
    commit -S -m "msg"
```

**Verification:**
- `git verify-commit` with `gpg.ssh.allowedSignersFile`
- `allowedSignersFile` lives in repo:
  `<chain>/.freechains/allowed_signers`
- Auto-generated from pioneers + known authors
- Format: `<email> ssh-ed25519 AAAA...`

### Resolved: verification flow

**Tested:** `%GK` returns fingerprint (`SHA256:...`), not
pubkey string. `%GP` empty. No `%G` format gives the pubkey.

**The pubkey is embedded in the SSH signature blob.**
Extract via `git cat-file commit` → decode `gpgsig` →
`string.unpack` (~15 lines Lua).

**Per-commit verification during replay:**
1. `cat-file commit <hash>` → parse signature → extract pubkey
2. Write single-entry `allowed_signers`: `<principal> <pubkey>`
3. `git verify-commit <hash>` → confirms valid signature
4. Pass pubkey to `apply()`

No persistent `allowed_signers` file needed.
No fingerprint→pubkey mapping needed.
No `%GK` usage.

### Implementation order

1. **Generate SSH test keys**
   - Create `tst/ssh-keys/` with 3 Ed25519 keypairs
   - `ssh-keygen -t ed25519 -N "" -f key1` (×3)
   - Generate `allowed_signers` from pubkeys
   - Replaces `tst/gnupg/`

2. **Update tests.lua**
   - `KEY = "tst/ssh-keys/key1"` (path to private key)
   - Extract pubkeys: `ssh-keygen -y -f <path>`
   - Remove `GNUPGHOME` dependency
   - Setup `allowed_signers` for verification

3. **Update genesis**
   - `genesis-*.lua`: pioneers = `{ "ssh-ed25519 AAAA..." }`
   - `chains.lua`: no changes (pioneers are opaque strings)

4. **Update post.lua**
   - Line 112: `-c gpg.format=ssh -c user.signingkey=<path>`
   - `ARGS.sign` = path to private key
   - Extract pubkey via `ssh-keygen -y -f` for `apply()`

5. **Update like** (shares post.lua code, inherits changes)

6. **Update sync.lua**
   - Extract pubkey from SSH signature blob per commit
     (`cat-file commit` → decode gpgsig → `string.unpack`)
   - Write ephemeral `allowed_signers` for verification
   - `git verify-commit` per commit
   - Pass extracted pubkey to `apply()`
   - Set `gpg.ssh.allowedSignersFile` in chain git config
