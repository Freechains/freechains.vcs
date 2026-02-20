# Signing: Git vs Freechains

| | Git | Freechains |
|---|---|---|
| Signing | Optional, external (GPG/SSH) | Structural, integral |
| Key management | External (`gpg`, `ssh-keygen`) | Built-in (`freechains keys`) |
| Identity | Email + key, loosely coupled | Public key **is** the identity |
| Unsigned content | Fully valid | Valid only on public chains |
| Signature affects hash | no — outside the hash | yes — inside the hash |
| Impersonation difficulty | Trivial (free text name/email) | Impossible (hash includes pubkey) |

## Why git's model is not fragile for its use case

Git's trust anchor is **the channel, not the data**. When you pull from `kernel.org`, trust comes from SSH authentication and server access controls — not from commit metadata. Rewriting history is detectable because hashes of all subsequent commits change, visible to everyone on next fetch. This would be fragile for Freechains because Freechains has **no trusted infrastructure** — the only thing peers can trust is the math.

## Where to embed Freechains signature in a git commit

| Option | In Hash | API ease | Human-readable log | Verdict |
|---|---|---|---|---|
| Commit message | yes | easy | ugly | good, simple |
| Extra headers | yes | raw object construction needed | preserved | **best, cleanest** |
| Author/committer fields | yes | easy | pubkey as name, awkward | works but hacky |
| GPG signature field | **no** | easy | preserved | wrong — outside hash |
| Git notes | **no** | easy | preserved | wrong — outside hash |

Recommended: **extra headers** (`freechains-pubkey`, `freechains-sig`) keep the message human-readable and put all cryptographic data inside the hash. Requires constructing raw commit objects but gives the cleanest separation.
