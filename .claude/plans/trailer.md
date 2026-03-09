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
  required, see merge-hook.md)
- Creates a record of which peer performed the sync and
  when (merge commit timestamp = peer's local clock)
- Enables peer reputation: peers that consistently
  witness and relay posts build a verifiable track record
  in the DAG

```
--trailer 'Freechains-Peer: CA6391CE...'
```

- Combined with GPG signing (`git commit -S`), this
  creates a signed attestation: "peer X saw this branch
  state at time T"
- Relevant to time-based rules (12h, 24h, 7-day) where
  peer witness timestamps could supplement or replace
  self-reported author timestamps (see threats.md T2a)

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
