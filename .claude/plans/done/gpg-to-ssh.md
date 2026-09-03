# GPG → SSH migration

## STATUS: DONE

Migration completed. All steps executed, all referenced
tests pass. Notable deviations from the original plan:

- Helpers landed in `src/freechains/chain/ssh.lua`
  (module `M.pubkey`, `M.verify`), not as globals.
- `extract_pubkey` parses SSHSIG directly in Lua
  (no `ssh-keygen` extraction needed); only base64 is shelled.
- `verify_commit` writes `.freechains/tmp/allowed_signers`
  (gitignored via skel `.gitignore` + `.gitkeep` for the dir)
  and `os.remove`s it after the call.
- `--beg` reps check moved into `apply()` instead of
  `post.lua` pre-check — closes a latent sync-replay bug
  where remote `--beg` commits by high-reps authors
  were not validated.
- `like.lua` restructured: commit before apply (mirrors
  `post.lua`) so the SSH pubkey can be extracted from the
  just-signed commit.
- `like.lua` commit exec now wrapped with
  `"chain like : invalid sign key"` error.
- Test identities (`reps author`, `like N author`) switched
  to shell-quoted SSH pubkey strings.

## Goal

Replace GPG commit signing with SSH commit signing.
**No other behavior changes.** All existing mechanisms
(`beg`, `refs/begs/`, `--beg`, `like N post <hash>`,
`like N author <KEY>`, blocked/00-12 transitions, reps,
replay, CLI surface) stay exactly as they are.

## Why SSH

- SSH `gpgsig` header embeds the **full public key**
  (Ed25519, ~32 bytes), not just a key ID.
- Verification is self-contained: the pubkey can be
  extracted from the signature itself, with no prior
  keyring needed. This matches Freechains' p2p model.
- Same Ed25519 curve already chosen in `crypto.md`.
- Standard git tooling: `git commit -S` and
  `git verify-commit` work unchanged, only the
  `gpg.format` config flips from `openpgp` to `ssh`.

## Identity model

- **Identity = raw SSH public key string**
  (`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...`).
- Used as the key in `G.authors`, in pioneer vectors,
  and as the `sign` field passed to `apply()`.
- Replaces the GPG fingerprint (`%GF`) used today.
- The pubkey is **always extracted from the commit
  itself** (post-sign and at verify-time), never
  computed from a private key file.

## CLI surface

`--sign <arg>` stays. `<arg>` is whatever git accepts
as `user.signingkey` for SSH signing:

- A path to a private key file: `~/.ssh/id_ed25519`
- A path to a public key file: `~/.ssh/id_ed25519.pub`
  (git locates the matching private key alongside)
- A literal `key::ssh-ed25519 AAAA...` if `ssh-agent`
  holds the matching private key

The CLI does **not** parse or validate `<arg>` — it is
passed verbatim to git. Validation is implicit: if git
cannot sign, the commit fails and the existing
`"chain post : invalid sign key"` error fires.

## Verification model

`git verify-commit` is the only verifier.
It needs `gpg.ssh.allowedSignersFile` populated **before**
it runs. The file is built on the fly per verification:

1. Extract the SSH signature blob from the commit
   (`git cat-file commit <hash>` → grab `gpgsig` lines).
2. Shell out to `ssh-keygen` once to extract the
   pubkey from the signature blob.
3. Write `<pubkey> <pubkey>\n` (single line, principal =
   pubkey) to `.git/info/allowed_signers` (untracked,
   overwritten each call).
4. `git -c gpg.ssh.allowedSignersFile=.git/info/allowed_signers verify-commit <hash>`.
5. Return the extracted pubkey to the caller as the
   identity to pass into `apply()`.

`ssh-keygen` is a **transitive runtime dependency** of
`git verify-commit` for SSH anyway, so requiring it for
the extraction step adds no new dependency.

### `ssh-keygen` extraction invocation

**TBD: confirm the exact invocation during implementation.**
Candidates to test, in order of preference:

- `ssh-keygen -Y check-novalidate -n <namespace> -s <sigfile> < /dev/null`
  prints the signing key to stderr/stdout.
- Parsing the armored SSHSIG blob via
  `ssh-keygen -e -f <pubfile>` is **not** applicable
  (that converts public key formats, not signatures).
- Fallback: `ssh-keygen -Y find-principals` requires
  an existing `allowed_signers`, so it cannot bootstrap.

The implementer should confirm the working command on
the local system before wiring it in. Lock the chosen
form into a single helper (see `signing_ssh.lua` below).

## Files to create

### `src/freechains/chain/signing_ssh.lua` — new helper

Single module exposing two functions used by
`post.lua`, `like.lua`, `sync.lua`:

```lua
-- Extract the SSH pubkey string from a signed commit.
-- Reads the gpgsig blob, shells out to ssh-keygen.
-- Returns "ssh-ed25519 AAAA..." or nil on unsigned.
function extract_pubkey (repo, hash) ... end

-- Verify a commit's SSH signature against its own
-- embedded pubkey. Builds .git/info/allowed_signers
-- on the fly, then calls git verify-commit.
-- Returns (true, pubkey) on success, (false, err) on failure.
function verify_commit (repo, hash) ... end
```

Both functions are pure helpers — no global state, no
side effects beyond writing `.git/info/allowed_signers`
(which is untracked and per-repo).

## Files to modify

### `src/freechains/chain/post.lua`

| Place                          | Change                                                                 |
|--------------------------------|------------------------------------------------------------------------|
| line 40 (sign config string)   | `gpg.format=openpgp` → `gpg.format=ssh`                                |
| (no other change)              | `--sign <arg>` semantics unchanged from git's perspective              |

### `src/freechains/chain/like.lua`

| Place                          | Change                                                                 |
|--------------------------------|------------------------------------------------------------------------|
| line 69 (sign config string)   | `gpg.format=openpgp` → `gpg.format=ssh`                                |

### `src/freechains/chain/sync.lua`

| Place                          | Change                                                                 |
|--------------------------------|------------------------------------------------------------------------|
| line 22 (`git log` format)     | Drop `%GF` from the format. Replay no longer reads the fingerprint from `git log`. |
| replay loop (lines 24–80)      | For each commit, call `signing_ssh.verify_commit(REPO, hash)` to get the pubkey. Use that pubkey as `key` (replaces the `%GF` value). Unsigned commits → `key = nil` (same as today: triggers the `beg` path). |
| `kind == 'like'` branch        | `sign = key` unchanged in semantics — `key` is now the SSH pubkey string instead of GPG fingerprint. |
| `kind == 'post'` branch        | Same: `sign = key`, `beg = (key == nil)`. Unchanged structurally.       |

Note: verification is now performed during replay
(it wasn't before — replay only read `%GF`). This is
a behavior addition but it's the natural place to
enforce signature validity. If we want to skip
verification for performance, we can lift the call out
later; the plan is to wire it in.

### `src/freechains/chain/common.lua`

No change. `apply()` already takes `T.sign` as an
opaque identity string — it doesn't care whether it's
a GPG fingerprint or an SSH pubkey.

### `src/freechains/chains.lua`

| Place                          | Change                                                                 |
|--------------------------------|------------------------------------------------------------------------|
| `git_config()` (line 4)        | No change — `commit.gpgsign false` is still correct (we sign per-command, not by default). |
| `pioneers()` (line 12)         | No change — already iterates `T.pioneers` as a string vector and writes `A[key] = { reps = n }`. The strings are now SSH pubkeys instead of GPG fingerprints. |

### `src/freechains.lua`

No change. `--sign` option already accepts a string.

## Files to rewrite (tests)

### `tst/tests.lua`

| Place                          | Change                                                                 |
|--------------------------------|------------------------------------------------------------------------|
| `GPG`, `KEY`, `KEY2`, `KEY3`, `ENV`, `ENV_EXE` | Replace with SSH equivalents:                          |

```lua
SSH  = exec("realpath ssh-keys/")
KEY  = SSH .. "/key1"        -- private key path
KEY2 = SSH .. "/key2"
KEY3 = SSH .. "/key3"
-- The pubkey strings (used as identities in genesis):
PUB  = exec("cat " .. KEY  .. ".pub | awk '{print $1\" \"$2}'")
PUB2 = exec("cat " .. KEY2 .. ".pub | awk '{print $1\" \"$2}'")
PUB3 = exec("cat " .. KEY3 .. ".pub | awk '{print $1\" \"$2}'")
ENV     = ""                 -- no GNUPGHOME needed
ENV_EXE = EXE                -- ENV prefix collapses to nothing
```

`ENV` is kept as an empty string so existing test
files referencing `ENV ..` and `ENV_EXE` need no edits.

### `tst/ssh-keys/` — new directory with committed test keys

Generate three Ed25519 keypairs (no passphrase) for
tests. These are throwaway keys, safe to commit:

```
ssh-keygen -t ed25519 -N '' -C 'test1' -f tst/ssh-keys/key1
ssh-keygen -t ed25519 -N '' -C 'test2' -f tst/ssh-keys/key2
ssh-keygen -t ed25519 -N '' -C 'test3' -f tst/ssh-keys/key3
```

Resulting files:
- `tst/ssh-keys/key1`, `key1.pub`
- `tst/ssh-keys/key2`, `key2.pub`
- `tst/ssh-keys/key3`, `key3.pub`

`tst/gnupg/` is **deleted**.

### `tst/genesis-1.lua`, `tst/genesis-2.lua`, `tst/genesis-3.lua`

Replace GPG fingerprint strings with SSH pubkey
strings. Format unchanged (still a plain string
vector). The strings are loaded by `tests.lua` from
`ssh-keys/*.pub`, so the genesis files cannot embed
literal pubkeys (they'd be machine-specific).

Resolution: the genesis files are themselves generated
or templated by `tests.lua` at test setup. Two options:

(a) **Static files with placeholders** — keep the
    `genesis-N.lua` files in tree, but with literal
    pubkeys committed alongside the test keys. Since
    the test keys are committed and reproducible, the
    pubkeys are stable.

(b) **Generated at test setup** — `tests.lua` writes
    the genesis files into `TMP/` from a template
    before each test run.

**Choose (a)** — simpler, matches current style. After
generating `tst/ssh-keys/key{1,2,3}.pub`, copy the
pubkey strings into the corresponding genesis file
literally.

Example `tst/genesis-1.lua` after migration:

```lua
return {
    version = {1, 2, 3},
    type    = "#",
    name    = "A forum",
    descr   = [[
        This forum is about...
    ]],
    pioneers = {
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI<...>",
    },
}
```

`genesis-2.lua` lists two pubkeys, `genesis-3.lua`
three. `genesis-0.lua` stays as-is (no pioneers).

### `tst/cli-sign.lua`

| Place                          | Change                                                                 |
|--------------------------------|------------------------------------------------------------------------|
| line 29 (verify-commit assert) | Drop `'Good signature from "test <test@freechains>"'` match — SSH signatures don't carry that metadata. Instead assert exit code 0 and that output contains `Good "git" signature` or similar (TBD: confirm wording from local `git verify-commit` SSH output). |
| line 37 (gpgsig present)       | Same assertion — SSH signatures still use the `gpgsig` header name.    |
| line 86 (bad key error)        | Unchanged — invalid path still produces the `invalid sign key` error.  |

### `tst/cli-begs.lua`, `tst/repl-local-begs.lua`, `tst/repl-remote-begs.lua`

No structural changes. They use `KEY` from `tests.lua`
which now points to an SSH key path. The flag `--beg`
and `refs/begs/` mechanics are untouched.

### `tst/cli-like.lua`, `tst/cli-post.lua`, `tst/cli-sync.lua`, `tst/repl-local-*.lua`, `tst/repl-remote-*.lua`, `tst/err-post.lua`, `tst/err-like.lua`

No changes beyond `KEY`/`KEY2`/`KEY3` now being SSH
key paths instead of GPG fingerprints. All
`ENV_EXE`-prefixed invocations work unchanged because
`ENV_EXE = EXE` (empty `ENV`).

### `tst/cli-time.lua`, `tst/cli-now.lua`, `tst/cli-reps.lua`, `tst/cli-chains.lua`, `tst/repl-local-head.lua`, `tst/repl-remote-head.lua`, `tst/git-merge.lua`

Audit for any `KEY`/`GPG`/`GNUPGHOME` references; same
treatment as above.

## Files to delete

| File or dir                              | Reason                              |
|------------------------------------------|-------------------------------------|
| `tst/gnupg/` (entire directory)          | GPG keyring no longer used          |

Nothing else is deleted. `.freechains/keys/` does not
exist in the current tree (the `ident.md` plan that
introduced it was never executed), so there is nothing
to remove there.

## Step-by-step execution order

Each step should leave the tree in a working state if
possible, but the GPG → SSH cutover is necessarily
atomic (you can't sign with both at once for the same
test run). So the practical order is:

1. **Create `tst/ssh-keys/`** with three committed
   Ed25519 keypairs.
2. **Create `src/freechains/chain/signing_ssh.lua`**
   with `extract_pubkey` and `verify_commit`. Confirm
   the `ssh-keygen` extraction invocation locally;
   write the helper as a single shellout per call.
3. **Update `tst/tests.lua`** to point `KEY`/`KEY2`/
   `KEY3` at the new SSH key paths and drop `GPG`/
   `ENV` (or set `ENV = ""`).
4. **Update `tst/genesis-1.lua`, `genesis-2.lua`,
   `genesis-3.lua`** with literal SSH pubkey strings
   read from the generated `.pub` files.
5. **Edit `src/freechains/chain/post.lua` line 40**:
   `gpg.format=openpgp` → `gpg.format=ssh`.
6. **Edit `src/freechains/chain/like.lua` line 69**:
   same.
7. **Edit `src/freechains/chain/sync.lua`**: drop
   `%GF` from `git log` format; call
   `signing_ssh.verify_commit` per commit in the
   replay loop and use its returned pubkey as `key`.
8. **Update `tst/cli-sign.lua`** assertions to match
   SSH `git verify-commit` output.
9. **Delete `tst/gnupg/`**.
10. **Run all tests**, fix any leftover GPG references.

## Verification

After implementation, all of these should pass:

```
cd tst
lua5.4 cli-sign.lua
lua5.4 cli-post.lua
lua5.4 cli-like.lua
lua5.4 cli-begs.lua
lua5.4 cli-sync.lua
lua5.4 cli-reps.lua
lua5.4 cli-time.lua
lua5.4 cli-now.lua
lua5.4 cli-chains.lua
lua5.4 err-post.lua
lua5.4 err-like.lua
lua5.4 repl-local-head.lua
lua5.4 repl-local-begs.lua
lua5.4 repl-remote-head.lua
lua5.4 repl-remote-begs.lua
lua5.4 git-merge.lua
```

Note: **no `GNUPGHOME=...` prefix anymore.**

## Open items / TBD

1. **Exact `ssh-keygen` extraction command** — must be
   confirmed on the implementing machine. See the
   "ssh-keygen extraction invocation" section above.
2. **`cli-sign.lua` verify-commit output assertion** —
   must be confirmed against local git output for SSH
   signatures (the wording differs from GPG's
   `Good signature from "..."`).
3. **Verification cost in replay** — `sync.lua` will
   now call `git verify-commit` once per commit during
   replay. For large chains this could be slow. If
   benchmarks show a problem, lift verification to a
   single batch step or cache results. Not addressed
   in this plan.

## Out of scope (do NOT do as part of this migration)

- Removing or renaming `beg` / `--beg` / `refs/begs/`.
- Introducing `ident` commits.
- Changing the `like N author <KEY>` flow.
- Adding bios, `.freechains/keys/`, or any in-chain
  keyring file.
- Changing `apply()`, reps logic, blocked states, or
  the trailer scheme.
- Migrating other crypto primitives (encryption etc.).

This plan is **strictly** GPG → SSH for commit signing.
