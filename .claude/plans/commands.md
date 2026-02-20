# Freechains Commands → Git Mapping

| Freechains Command | Git Equivalent | Match (1–5) | Notes |
|---|---|---|---|
| `freechains-host start <dir>` | `git init` + `git daemon` | 3 | init is close; daemon is a separate persistent process |
| `freechains chains join <chain>` | `git clone` | 4 | each chain is its own repo; cloning = joining |
| `freechains chains leave <chain>` | delete local repo + `git remote remove` | 3 | git has no single command for this |
| `freechains chains list` | `ls` of cloned repos | 3 | no native multi-repo listing in git |
| `freechains chain <n> genesis` | `git rev-list --max-parents=0 HEAD` | 4 | finding root commit, very close |
| `freechains chain <n> heads` | `git rev-parse HEAD` | 4 | single HEAD model simplifies this to one command |
| `freechains chain <n> get block <hash>` | `git cat-file -p <hash>` | 5 | direct content-addressed lookup, perfect |
| `freechains chain <n> get payload <hash>` | `git cat-file blob <hash>` | 5 | blob = payload, perfect match |
| `freechains chain <n> post inline <text>` | `git hash-object` + `git commit` | 3 | must write blob + tree before committing |
| `freechains chain <n> like <hash>` | zero-payload commit with `freechains-like: <hash>` extra header | 1 | stored as structural commit with metadata only |
| `freechains chain <n> dislike <hash>` | zero-payload commit with `freechains-dislike: <hash>` extra header | 1 | same pattern as like |
| `freechains chain <n> reps <hash_or_pub>` | walk `git log`, accumulate like/dislike headers, cache in SQLite | 1 | computed state, not stored in git |
| `freechains chain <n> consensus` | `git log --date-order` skipping sync commits | 3 | deterministic but not the same rule; skip `freechains-sync: true` commits |
| `freechains chain <n> listen` | `post-receive` git hook on server | 3 | fires server-side after every push; see hooks below |
| `freechains peer <addr> ping` | `git ls-remote <remote>` | 2 | tests reachability but does much more |
| `freechains peer <addr> chains` | `ls` of repos served by remote `git daemon` | 2 | no standard discovery protocol in git |
| `freechains peer <addr> send <chain>` | `git push` | 4 | strong match, both client-server |
| `freechains peer <addr> recv <chain>` | `git fetch` + `git merge` | 4 | fetch alone not enough — must merge to integrate; always produces a merge commit |
| `freechains keys shared <passphrase>` | libsodium `crypto_secretbox_keygen` via luasodium | 1 | implement in Lua |
| `freechains keys pubpvt <passphrase>` | libsodium `crypto_sign_keypair` via luasodium | 1 | implement in Lua |

---

## Git Hooks

Git hooks are shell scripts executed automatically at specific points in git's workflow. They live in `.git/hooks/`. Relevant hooks for Freechains:

| Hook | Runs when | Side | Use for Freechains |
|---|---|---|---|
| `post-receive` | After a `git push` is received and written | **Server** | Trigger consensus recomputation, notify listeners — closest analog to `chain listen` |
| `pre-receive` | Before objects are written on push | **Server** | Validate block signatures before accepting — reject invalid blocks |
| `update` | Once per ref being updated on push | **Server** | Per-chain signature validation |
| `post-merge` | After a `git merge` completes locally | **Client** | Trigger SQLite reputation cache update |
| `post-commit` | After a local commit | **Client** | Trigger local consensus refresh |

`post-receive` is the key one — it fires on the server side every time a peer pushes, which is exactly when new blocks arrive. Combined with `pre-receive` for signature validation, you get the full Freechains block acceptance pipeline as git hooks.
