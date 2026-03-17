# Genesis Block

## Status: Revision

Redesigning genesis to use `.freechains/config.lua` with
embedded constants.
Previous implementation used `.genesis.lua`.

## Spec

The genesis block is the first and oldest block in a chain.
It uses the creator's real public key and the current timestamp,
so two calls to `chains add` with identical parameters produce
different chain hashes.
The commit hash of the genesis block is the
**unique identifier of the chain**.

### Creation

```
freechains chains add <alias> <dir>/
freechains chains add <alias> clone <url>/<chain>
```

The `<dir>/` becomes the genesis commit tree.
It must contain `.freechains/config.lua` (mandatory).
It may contain `.freechains/authors.lua` (optional, for
pioneers in public chains).
It may contain any other files — scripts, PDFs, seed data,
templates, etc.

On creation, `.freechains/config.lua` is validated:
all required fields must be present (omission is an error).

The `clone` form fetches an existing chain from a peer.
`<chain>` can be a genesis hash or an alias on the remote.
On clone, the received `config.lua` is validated the same way.

### Config file: `.freechains/config.lua`

Replaces the old `.genesis.lua` and the global
`constants.lua`.
Each chain carries its own full set of rules.
There is no global `constants.lua` fallback — every field
must be present.

```lua
return {
    version = {0, 11, 0},
    type    = '#',              -- '#' | '$' | '@' | '@!'
    -- shared = "x25519:def...",     -- '$' only
    -- key    = "ed25519:abc...",    -- '@'/'@!' only
    time = {
        future  = 3600,         -- max post future tolerance
        half    = 43200,        -- halfway discount period
        full    = 86400,        -- fullway consolidation period
    },
    reps = {
        unit    = 1000,         -- 1 ext rep = 1000 internal
        cost    = 1000,         -- 1 ext per signed post
        max     = 30000,        -- 30 ext cap per author
    },
    like = {
        tax   = 10,             -- 10% burned on likes
        split = 2,              -- 50/50 split (divisor)
    },
}
```

### Fields

#### `version`

Array of three integers `{major, minor, patch}` identifying the
protocol version.
Two peers must share the same major version to synchronize.
Version is checked on sync — incompatible versions are rejected.

#### `type`

A character string defining the access policy of the chain.

| Char  | Type                    |
|-------|-------------------------|
| `'#'` | public                  |
| `'$'` | private                 |
| `'@'` | personal (read-only)    |
| `'@!'`| personal (writeable)    |

See [Chains](chains.md) for details on each type.

#### `shared`

An X25519 shared key for encrypted communication.
Only relevant for private (`'$'`) chains.

#### `key`

An Ed25519 public key identifying the chain owner.
Only relevant for personal (`'@'` / `'@!'`) chains.

#### `time`

Time-related constants for the chain.
All values in seconds.

| Field    | Description                           |
|----------|---------------------------------------|
| `future` | Max clock drift tolerance for posts   |
| `half`   | Halfway post discount period          |
| `full`   | Full post consolidation period        |

#### `reps`

Reputation constants for the chain.

| Field  | Description                          |
|--------|--------------------------------------|
| `unit` | Internal units per 1 external rep    |
| `cost` | Rep cost per signed post             |
| `max`  | Max rep cap per author               |

#### `like`

Like/dislike constants for the chain.

| Field   | Description                         |
|---------|-------------------------------------|
| `tax`   | Percentage burned on likes          |
| `split` | Divisor for like split (2 = 50/50)  |

### Authors file: `.freechains/authors.lua` (optional)

Defines pioneer keys and their initial reputation.
Optional — if absent, the chain has no pioneers (fully open
public chain).

```lua
return {
    ["ed25519:abc..."] = 10000,
    ["ed25519:def..."] = 10000,
}
```

### Arbitrary initial files

The genesis directory may contain any additional files.
These become part of the genesis commit tree and thus part
of the chain identity hash.
Use cases: scripts, documentation, templates, seed data.

### Immutability

`.freechains/config.lua` is **immutable** after chain creation.
No commit may alter its content.
Validation details in [consensus.md](consensus.md).

### Hash

The genesis hash is the **git commit hash** of the genesis
commit:

```
genesis_hash = git_commit_hash(genesis)
```

This means:
- Each `chains add` call produces a unique chain identity
- The creator's pubkey and current timestamp make the hash
  unique
- `create` and `clone` are distinct operations
- To join an existing chain, use `chains add <alias> clone`

### Git Mapping

The genesis block corresponds to the **first commit** of a git
repository.
Author/committer are left blank (no signing yet).
The genesis tree is the entire contents of the user-provided
directory.

| Field            | Value                                        |
|------------------|----------------------------------------------|
| tree             | contents of `<dir>/` (must include `.freechains/config.lua`) |
| parent           | none                                         |
| author name      | blank                                        |
| author email     | blank                                        |
| author date      | current timestamp (git default)              |
| committer name   | blank                                        |
| committer email  | blank                                        |
| committer date   | current timestamp (git default)              |
| message          | empty                                        |

Two calls with the same parameters produce **different** commit
hashes (different timestamps), creating distinct chains.

---

## Key Design Decisions

### Hash = identity

```
genesis_hash = git_commit_hash(genesis)
```

Each genesis commit is unique because it includes the current
timestamp (via git defaults).
All files in the genesis directory are part of the commit tree
and thus part of the hash.

### Config replaces constants

Each chain carries its own rules in `.freechains/config.lua`.
There is no global `constants.lua`.
This allows different chains to have different time windows,
reputation caps, like taxes, etc.
Every field is mandatory — omission is a validation error.

### Directory as genesis input

The genesis commit tree is not limited to config files.
Any files in the provided directory become part of the chain's
initial state.
This enables chains with seed content, documentation, or
application-specific resources.

## Test Coverage

| #     | What                                       | Assertions |
|-------|--------------------------------------------|------------|
| 1–2   | Basic creation (commit type, HEAD)         | 2          |
| 3     | No parent                                  | 1          |
| 4     | Tree contains `.freechains/config.lua`     | 1          |
| 5–6   | Author/committer name = blank              | 2          |
| 7–8   | Author/committer email = blank             | 2          |
| 9     | Message = empty                            | 1          |
| 10    | Uniqueness: same params → different hash   | 1          |
| 11    | `config.lua` content matches input         | 1          |
| 12    | Chain ID = commit hash, valid hex          | 1          |
| 13    | Symlink alias → hash directory             | 1          |
| 14    | Arbitrary files in genesis dir preserved   | TBD        |
| 15    | Missing config.lua → error                 | TBD        |
| 16    | Missing required field → error             | TBD        |
| 17    | Clone validates config.lua                 | TBD        |
| **Total** |                                        | **17**     |
