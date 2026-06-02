# Freechains 0.11: Chains

A chain is a topic in the publish-subscribe model of Freechains.
It is a Merkle DAG of blocks linked from a set of heads down to
the [genesis block](genesis.md).
Peers synchronize their chains to disseminate content across the
network.

## Identification

A chain is univocally identified by its **typed genesis hash**:

```
chain_id = <type> .. git_commit_hash(genesis)
```

`<type>` is the type character from the genesis block
(currently only `#`).
Each `chains add init` call creates a unique genesis commit
(real pubkey + timestamp), so the chain id is unique per creation.
To join an existing chain, use `chains add <alias> clone <url>`.

The type prefix shares its shape with aliases (`#sports`),
making any chain id self-describing.
Aliases beyond the prefix remain application-layer conventions.

## Types

Freechains supports three chain types, determined by the `type`
character in the genesis block.

### Public Forum (`'#'`)

`N<->N` communication among untrusted participants.
Relies on the reputation system to prevent SPAM and abuse.

```lua
return {
    version  = {0, 11, 0},
    type     = '#',
}
```

Pioneers are defined by their non-zero entries in
`local/authors.lua`, initialized from `genesis.lua`
pioneers at chain creation/clone.
A chain with no pioneers (empty `local/authors.lua`) is
fully open — anyone can post from the start.

### Private Group (`'$'`)

Encrypted communication among trusted peers.
Covers `1<->1`, `N<->N`, and `1<-` (self) use cases.

```lua
return {
    version = {0, 11, 0},
    type    = '$',
    shared  = "x25519:def...",
}
```

All users with the shared key have infinite reputation and are
not required to sign messages.
All posts are automatically encrypted on creation and decrypted
on receipt.

### Personal (`'@'` / `'@!'`)

`1->N` broadcasting with optional `1<-N` feedback.

```lua
return {
    version = {0, 11, 0},
    type    = '@',              -- read-only
    key     = "ed25519:abc...",
}
```

```lua
return {
    version = {0, 11, 0},
    type    = '@!',             -- writeable (feedback mode)
    key     = "ed25519:abc...",
}
```

The key holder has infinite reputation.
With `'@'`, only the key holder can post.
With `'@!'`, others may also post (e.g. encrypted feedback to
the owner).

## Synchronization

Peers identify chains by genesis hash, not by name.
The hash is used as the remote name in the Git layer:

```bash
# add a peer for a known chain
git remote add <chain-id> https://<peer>:8330/<chain-id>

# synchronize
git fetch <chain-id>
git push <chain-id>
```

To join an existing chain from a peer:

```bash
freechains chains add #myalias clone <url>
```

## Index and Aliases

Each peer maintains a local index mapping human-readable aliases
to genesis hashes.
Aliases are symlinks in the `chains/` directory:

```
<root>/chains/
  <chain-id>/              git repo (working tree)
  #sports -> <chain-id>/   symlink alias
  $family -> <chain-id>/   symlink alias
  @me     -> <chain-id>/   symlink alias
```

Aliases are **local to each peer** — two peers may use different
aliases for the same chain.
The genesis hash is always the authoritative identifier.

Aliases **must start with the type marker** (`#`, `$`, `@`) — the
same one in the genesis `type` field.
`chains add <alias> ...` rejects aliases without a type marker.
Currently only `#` is implemented; `$` and `@` are reserved.

## Layers

```
┌─────────────────────────────────────────┐
│  Application                            │
│  interprets user field, aliases,        │
│  naming conventions, hierarchies        │
├─────────────────────────────────────────┤
│  Freechains                             │
│  validates genesis, applies reputation  │
│  and consensus                          │
├─────────────────────────────────────────┤
│  Git                                    │
│  stores blocks as commits,              │
│  synchronizes peers by genesis hash     │
└─────────────────────────────────────────┘
```
