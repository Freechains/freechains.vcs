# Genesis

- the FIRST commit of the chain: the only root, no parents
- its commit hash IS the chain identity (`chains/<hash>/`)
- kept at `refs/genesis`, and it is never an action
- not replayed: it is the floor every replay starts above

# Format

- the whole spec is the commit MESSAGE, positional
- may arrive from a REMOTE peer, so parsed by match, never
  `load`

```
0.21.0
3004508805
dictators:
ssh-ed25519 AAAAC3Nz...IBhr
ssh-ed25519 AAAAC3Nz...ILTm
pioneers:
ssh-ed25519 AAAAC3Nz...IAqH
```

- line 1: version, `<major>.<minor>.<patch>`
- line 2: nonce, a random integer
- then the two key sections, in this exact order

# Canonical form

- one author set has exactly ONE encoding
- both headers are ALWAYS present, even when empty
    - an open chain states it, instead of being inferred
- the order is fixed: `dictators:` then `pioneers:`
- each section is sorted, so two peers emit the same bytes
- strict lines: every line ends in `\n`, none is empty
- a key line is `ssh-<type> <base64>`, nothing else
- the bytes ARE the chain id: a different genesis is simply a
  different chain, so this buys canonicity, not defense

# Nonce

- two `chains add` with the SAME keys must not collide
- dates cannot do it: they are neutral (`0 +0000`) so that
  creator and cloner agree byte for byte
- so a random integer makes the identity unique

# Derived state

- `pioneers` split the cap: `C.reps.max // #pioneers` each
    - `50000 // 1` = 50000, `// 2` = 25000, ...
    - refused when the share drops below `C.reps.cost`
- `dictators` start at 0 reps, and carry `dictator = true`
    - never gated, and their side wins a fork outright
    - ordinary authors otherwise: they pay, mint, cap, may owe
    - no cap on how many: they split nothing
- a key may hold BOTH roles: it takes the split AND the mark
- `open` = no pioneers and no dictators
    - the gates are skipped, and balances may go negative

# Commit fields

- tree: the EMPTY tree, as every commit in the chain
- parents: none (the only root)
- author/committer: `-` `<->`, date `0 +0000`
- message: the format above
- unsigned: the genesis grants, it does not claim

# Errors

- `expected commit`  : `refs/genesis` is not a commit
- `expected version` : line 1
- `expected nonce`   : line 2
- `expected newline` : the message does not end in `\n`
- `unexpected empty line` : a blank line inside the message
- `expected dictators` / `expected pioneers` : missing header
- `unexpected pioneers` : the header appears twice
- `invalid key`      : a line that is neither header nor key
- `too many pioneers`: the split drops below a post's cost

# History

- v0.21 introduced the sections; v0.20 wrote bare pioneer
  lines, with no headers
- there is NO back compatibility: a v0.20 genesis is refused
