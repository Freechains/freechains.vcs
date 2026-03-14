# Git Trailers in Freechains

## Current Usage

One trailer: `freechains: <kind>` where kind is `post` or
`like`.

```
git commit --trailer 'freechains: post' ...
git commit --trailer 'freechains: like'  ...
```

Used in `src/freechains:330` for every chain commit.

## Plan

### 1. Rename `freechains:` to `Freechains-Kind:`

- Conventional trailer capitalization
- Values: `post`, `like`

```
--trailer 'Freechains-Kind: post'
--trailer 'Freechains-Kind: like'
```

### 2. Add `Freechains-Ref: <commit-hash>`

- Explicit back-reference to the target post
- Added on like/dislike commits (and future quote/reply)
- Redundant with `.freechains/likes/*.lua` payload, which is
  the canonical source via `dofile()`
- Useful for quick `git log` queries without loading lua

```
--trailer 'Freechains-Kind: like'
--trailer 'Freechains-Ref: abc123def456'
```

### 3. Add `Freechains-Peer: <pubkey>` on merge commits

- Peers sign merge commits and identify themselves
- Merge commits already exist at sync time (`--no-ff`
  required, see [merge.md](merge.md) §3)
- The git author field already records the committer, but
  `Freechains-Peer:` records the peer's **chain-level
  public key** — the identity that matters for reputation

```
--trailer 'Freechains-Peer: CA6391CE...'
```

- Combined with GPG signing (`git commit -S`), this
  creates a signed attestation: "peer X saw this branch
  state at time T"

#### Peer reputation

- Each signed merge is a verifiable act of service:
  the peer fetched, validated consensus, and committed
- Peers that consistently relay content build a track
  record in the DAG — countable via
  `git log --grep='Freechains-Peer: <key>'`
- A peer's merge count is a measure of participation
  and reliability, independent of authoring content
- Enables trust decisions: prefer syncing with peers
  that have a long, visible history of honest merges
- Unlike author reputation (which flows from likes),
  peer reputation is earned by doing work that is
  costly to fake — you must actually fetch and validate

## Notes

- Finding the lua file in a commit is trivial:
  `git diff-tree --no-commit-id --name-only -r <hash>`
  returns the single changed file, then `dofile()` it.
- Parsing `.lua` payloads is preferred over parsing trailers,
  since we already have a lua interpreter.
- Trailers are part of the commit message, so they replicate
  and sign automatically.
- Multiple `--trailer` flags combine in a single `git commit`.

## Status

- [ ] Rename `freechains:` → `Freechains-Kind:`
- [ ] Add `Freechains-Ref:` to like/dislike commits
- [ ] Add `Freechains-Peer:` to merge commits
