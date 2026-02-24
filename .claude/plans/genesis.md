# Genesis Block

## Status: Done

Implemented in `tst/x1.sh` (26 assertions).

## Spec

The genesis block is the first and oldest block in a chain.
It is the same in all peers, since it is derived deterministically from
its parameters.
The hash of the genesis block is the **unique identifier of the chain**.

### Structure

```lua
local genesis = {
    version = {0, 11, 0},   -- protocol version
    type = {
        name      = "public",   -- "public" | "private" | "personal"
        keys      = {
            -- pioneers = {"ed25519:abc...", "ed25519:xyz..."},  -- public
            -- personal = "ed25519:abc...",                      -- personal
            -- shared   = "x25519:def...",                       -- private
        },
        writeable = true,       -- only relevant if name == "personal"
    },
    user = nil,   -- any value, opaque to the protocol
}
```

### Fields

#### `version`

Array of three integers `{major, minor, patch}` identifying the protocol
version.
Two peers must share the same major version to synchronize.

#### `type`

Defines the access policy of the chain. It is **immutable** — it cannot
change without creating a new chain.

- `name`: one of `"public"`, `"private"`, or `"personal"`
- `keys`: cryptographic keys that depend on `name` (see [Chains](chains.md))
- `writeable`: if `false`, only the personal key holder can post
  (only relevant when `name == "personal"`)

#### `user`

An arbitrary value, opaque to the protocol. The application layer interprets
its contents. It **does not enter the genesis hash** — two peers with the
same `(version, type)` but different `user` values share the same chain
identity.

The `user` field is typically used to carry application metadata such as
topic names, namespaces, or configuration.

### Hash

The genesis hash is computed over `(version, type)` only:

```
genesis_hash = HASH(version, type)
```

This means:
- The chain identity is fully determined at creation time
- Any peer using the same `version` and `type` parameters reaches the same
  initial state
- There are no "creators" — `join` is used instead of `create`

### Git Mapping

In the Git-based implementation, the genesis block corresponds to the
**first commit** of the repository.
The commit is made deterministic by zeroing all author/timestamp fields:

```bash
GIT_AUTHOR_NAME="freechains" \
GIT_AUTHOR_EMAIL="freechains" \
GIT_AUTHOR_DATE="1970-01-01T00:00:00+0000" \
GIT_COMMITTER_NAME="freechains" \
GIT_COMMITTER_EMAIL="freechains" \
GIT_COMMITTER_DATE="1970-01-01T00:00:00+0000" \
git commit --allow-empty -m "<serialized genesis>"
```

Two peers running this with identical parameters produce the same commit hash,
which becomes the chain identifier used in all peer synchronization.

---

## Key Design Decisions

### Hash = identity

```
genesis_hash = HASH(version, type)
```

The `user` field is excluded — two peers with the same `(version, type)` but
different `user` values share the same chain identity.

### Canonical serialization

The commit message is a canonical Lua-style literal of `(version, type)`:
- Keys sorted alphabetically at each level
- Pioneer lists sorted for determinism
- `writeable` included only for personal chains (defaults to `true`)

Examples:
```
{type={keys={},name="public"},version={0,11,0}}
{type={keys={pioneers={"ed25519:abc","ed25519:xyz"}},name="public"},version={0,11,0}}
{type={keys={shared="x25519:def123"},name="private"},version={0,11,0}}
{type={keys={personal="ed25519:mypub"},name="personal",writeable=true},version={0,11,0}}
```

### Git mapping

Genesis = first commit of a bare repo, made deterministic by zeroing all fields:

| Field | Value |
|---|---|
| tree | empty tree (`git hash-object -t tree /dev/null`) |
| parent | none |
| author name | `freechains` |
| author email | `freechains` |
| author date | `1970-01-01T00:00:00+0000` |
| committer name | `freechains` |
| committer email | `freechains` |
| committer date | `1970-01-01T00:00:00+0000` |
| message | canonical serialization of `(version, type)` |

Two peers running `genesis_create` with identical parameters produce the same
commit hash. No "creators" — `join` is used instead of `create`.

## Test Coverage (`tst/x1.sh`)

| # | What | Assertions |
|---|---|---|
| 1–2 | Basic creation (commit type, HEAD) | 2 |
| 3 | No parent | 1 |
| 4 | Empty tree | 1 |
| 5–6 | Author/committer = "freechains" | 4 |
| 7 | Dates = epoch zero | 2 |
| 8 | Message = canonical serialization | 1 |
| 9 | Determinism: same params → same hash | 1 |
| 10–11 | Different version/type → different hash | 2 |
| 12 | user excluded from hash | 1 |
| 13–15 | Public chain with pioneers (canonical sort) | 3 |
| 16–17 | Private chain with shared key | 2 |
| 18–19 | Personal chain (writeable=true/false) | 2 |
| 20 | writeable flag changes hash | 1 |
| 21 | Personal defaults writeable=true | 1 |
| 22–23 | Chain ID matches across peers, valid hex | 2 |
| **Total** | | **26** |

## Shell Helpers

- `genesis_serialize <major> <minor> <patch> <type_name> [key=value ...]` — canonical message
- `genesis_create <repo> <major> <minor> <patch> <type_name> [key=value ...]` — create commit, return hash
