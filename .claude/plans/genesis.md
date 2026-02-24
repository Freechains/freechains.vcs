# Genesis Block

The genesis block is the first and oldest block in a chain.
It is deterministic — derived entirely from its parameters — so all peers
produce the same commit hash, which becomes the **unique chain identifier**.

## Status: Done

Implemented in `tst/x1.sh` (26 assertions).

## Structure

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
