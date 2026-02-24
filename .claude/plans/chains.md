# Freechains 0.11: Chains

A chain is a topic in the publish-subscribe model of Freechains.
It is a Merkle DAG of blocks linked from a set of heads down to the
[genesis block](genesis.md).
Peers synchronize their chains to disseminate content across the network.

## Identification

A chain is univocally identified by its **genesis hash**:

```
genesis_hash = HASH(version, type)
```

This hash is used directly in peer synchronization.
Names, prefixes, and aliases are conventions of the application layer
and are not part of the protocol.

## Types

Freechains supports three chain types, determined by `type.name` in the
genesis block.

### Public Forum (`"public"`)

`N<->N` communication among untrusted participants.
Relies on the reputation system to prevent SPAM and abuse.

```lua
type = {
    name     = "public",
    keys     = {
        pioneers = { "ed25519:abc...", "ed25519:xyz..." },
    },
    writeable = true,
}
```

Pioneers are listed in the genesis and start with elevated reputation.
A chain with no pioneers is fully open — anyone can post from the start.

### Private Group (`"private"`)

Encrypted communication among trusted peers.
Covers `1<->1`, `N<->N`, and `1<-` (self) use cases.

```lua
type = {
    name     = "private",
    keys     = {
        shared = "x25519:def...",
    },
    writeable = true,
}
```

All users with the shared key have infinite reputation and are not required
to sign messages. All posts are automatically encrypted on creation and
decrypted on receipt.

### Personal (`"personal"`)

`1->N` broadcasting with optional `1<-N` feedback.

```lua
type = {
    name      = "personal",
    keys      = {
        personal = "ed25519:abc...",
    },
    writeable = false,   -- true allows others to post (feedback mode)
}
```

The personal key holder has infinite reputation.
If `writeable = false`, only the key holder can post.
If `writeable = true`, others may post (e.g. encrypted feedback to the owner).

## Synchronization

Peers identify chains by genesis hash, not by name.
The hash is used as the remote name in the Git layer:

```bash
# add a peer for a known chain
git remote add <genesis_hash> https://<peer>:8330/<genesis_hash>

# synchronize
git fetch <genesis_hash>
git push <genesis_hash>
```

## Index and Aliases

Each peer maintains a local index mapping human-readable aliases to genesis
hashes. This file is itself a Git repository, making the alias history
versioned and inspectable by other peers.

```lua
-- ~/.freechains/index.lua
return {
    ["#sports"]  = "A95B969D...",
    ["$family"]  = "C40DBB98...",
    ["@johndoe"] = "B2853F45...",
}
```

Aliases are **local to each peer** — two peers may use different aliases for
the same chain. The genesis hash is always the authoritative identifier.

Prefix conventions (`#`, `$`, `@`) are application-level notation and carry
no meaning to the protocol.

## Layers

```
┌─────────────────────────────────────────┐
│  Application                            │
│  interprets user field, aliases,        │
│  naming conventions, hierarchies        │
├─────────────────────────────────────────┤
│  Freechains                             │
│  validates genesis, manages pioneers,   │
│  applies reputation and consensus       │
├─────────────────────────────────────────┤
│  Git                                    │
│  stores blocks as commits,              │
│  synchronizes peers by genesis hash     │
└─────────────────────────────────────────┘
```
