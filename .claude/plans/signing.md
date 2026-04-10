# Signing: SSH commit signatures

## Decision: SSH signing via `git commit -S` with `gpg.format=ssh`

Freechains signs commits with SSH keys (Ed25519).
The `gpgsig` header carries an SSHSIG blob that embeds
the **full public key**, so any node can verify a commit
without prior knowledge of the signer — matching the p2p
trust model.

## How git signing works

1. Git builds the commit content (tree, parent, author,
   committer, message) — call this the **payload**.
2. Git signs the payload → SSHSIG blob.
3. Git injects the `gpgsig` header into the commit object.
4. The commit hash (SHA-1) is computed over the **full
   object including `gpgsig`**.
5. To verify, git strips `gpgsig`, recovers the payload,
   checks the signature against an `allowed_signers` file.

### What the signature covers

| Field            | Signed | In hash |
|------------------|--------|---------|
| tree             | yes    | yes     |
| parent(s)        | yes    | yes     |
| author           | yes    | yes     |
| committer        | yes    | yes     |
| message          | yes    | yes     |
| gpgsig           | no (1) | yes     |

(1) The signature cannot cover itself — circular.
The signature covers everything else.

**Stripping a signature changes the commit hash.**
Signed and unsigned versions are different objects.

## Why SSH (not GPG)

GPG signatures only carry the **key ID**, not the public
key.
Verification requires the signer's pubkey in the local
keyring — impossible in a trustless p2p network.

SSHSIG embeds the **full pubkey** in the signature blob,
so verification is self-contained.

| Property                          | GPG          | SSH          |
|-----------------------------------|--------------|--------------|
| Pubkey in signature               | no (key id)  | **yes**      |
| Self-validating                   | no           | **yes**      |
| Keyring required                  | yes          | no           |
| Signature in commit hash          | yes          | yes          |
| Tamper-evident                    | yes          | yes          |
| Tooling                           | gpg          | ssh-keygen   |

## Identity model

- **Identity = SSH pubkey string**:
  `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...`
- Used as the key in `G.authors`, in genesis pioneer
  vectors, and as the `sign` field passed to `apply()`.
- The pubkey is **always extracted from the commit
  itself** at sign-time and verify-time.
  Never derived from a key file by Freechains.

### Pioneer format in `genesis-*.lua`

```lua
pioneers = {
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI<...>",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI<...>",
}
```

Plain string vector. Each entry is the full SSH pubkey
(type + base64 body, no comment).

## CLI surface

```
freechains chain <alias> post   ... --sign <arg>
freechains chain <alias> like N ... --sign <arg>
```

`<arg>` is whatever git accepts as `user.signingkey` for
SSH signing:

- private key path: `~/.ssh/id_ed25519`
- public key path: `~/.ssh/id_ed25519.pub`
- literal `key::ssh-ed25519 AAAA...` (if `ssh-agent`
  holds the matching private key)

Freechains does **not** parse `<arg>`.
It is passed verbatim to `git -c user.signingkey=<arg>`.
If git cannot sign, the commit fails and the existing
`"chain post : invalid sign key"` /
`"chain like : invalid sign key"` error fires.

## Helpers: `src/freechains/chain/ssh.lua`

Module exposing two functions:

### `M.pubkey(repo, hash)`

Extracts the SSH pubkey from a signed commit.

1. `git -C <repo> cat-file commit <hash>` → capture.
2. If no `gpgsig` line → return `nil` (unsigned).
3. Walk lines, collect the gpgsig header + continuation
   lines (start with space), strip BEGIN/END armor.
4. base64-decode (shell), parse SSHSIG header in Lua:
   skip `SSHSIG`(6B) + version(4B), read uint32 BE
   length, slice the pubkey wire-format bytes.
5. base64-encode (shell) → return
   `"ssh-ed25519 " .. body`.

Three shellouts total: `git cat-file`, `base64 -d`,
`base64 -w0`.
No `ssh-keygen` needed for extraction.

### `M.verify(repo, hash)`

Verifies a commit's SSH signature against its embedded
pubkey.

1. `key = M.pubkey(repo, hash)`.
2. If `key == nil` → return `nil` (unsigned).
3. Write `"git " .. key .. "\n"` to
   `<repo>/.freechains/tmp/allowed_signers`.
4. `git -C <repo>
       -c gpg.ssh.allowedSignersFile=.freechains/tmp/allowed_signers
       verify-commit <hash>`.
5. `os.remove` the allowed_signers file.
6. Return `key` on exit 0, `nil` on failure.

`.freechains/tmp/` is created at chain init via skel
(`.gitkeep` + `.gitignore` rule for the dir contents).

## Sign-and-identify flow (post.lua, like.lua)

Both commands sign the commit first, then extract the
pubkey from the just-signed commit and pass it to
`apply()` as `T.sign`:

```lua
exec("git ... -c gpg.format=ssh -c user.signingkey="
     .. ARGS.sign .. " commit -S ...",
     "chain post : invalid sign key")
local hash = exec("git rev-parse HEAD")
apply(G, 'post', now, {
    hash = hash,
    sign = ARGS.sign and ssh.pubkey(REPO, hash),
    beg  = ARGS.beg,
})
```

If `apply()` rejects (insufficient reputation, --beg
with reps>0, etc.), the commit is rolled back with
`git reset --hard HEAD~1`.

## Replay flow (sync.lua)

`replay()` walks `git log --reverse --no-merges
--format='%H %at'` over the new commits and, for each,
calls `ssh.pubkey(REPO, hash)` to obtain the signer
identity.
Unsigned commits → `key = nil` → triggers `--beg`
semantics in `apply()`.

`%GF` is **not** used — it's GPG-only and broken on SSH
signatures (returns `error: gpg.ssh.allowedSignersFile
needs to be configured...`).

`replay()` does **not** currently call `ssh.verify()`
per commit. Verification is implicit at merge time
(future: pre-merge-commit hook). Cost-of-verification
in replay is an open optimization question.

## Tests

- `tst/ssh.lua` — unit tests for `pubkey`/`verify`:
  roundtrip, good verify, unsigned, tampered, multiple
  keys.
- `tst/cli-sign.lua`, `cli-like.lua`, `cli-begs.lua`,
  `cli-sync.lua` — call `ssh.verify()` instead of raw
  `git verify-commit` to obtain the pubkey.
- `tst/ssh/key{1,2,3}` — committed Ed25519 keypairs
  (Alice/Bob/Charlie) used by all signing tests.
- Test identities are referenced via `PUB1`/`PUB2`/`PUB3`
  (loaded from `.pub` files in `tst/tests.lua`),
  shell-quoted when passed to `reps author` or
  `like N author`.

## Out of scope

- In-chain identity commits / register phase / PKI.
- `freechains keys` command, name → key registry.
- Encryption (separate concern, see `crypto.md`).
- Pre-merge-commit verification hook.
- Per-replay signature verification optimization.
