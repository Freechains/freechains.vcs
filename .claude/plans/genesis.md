# Genesis Block

## Status: In progress

CLI implementation pending in `src/freechains`.

## Spec

The genesis block is the first and oldest block in a chain.
It uses the creator's real public key and the current timestamp,
so two calls to `chains add` with identical parameters produce
different chain hashes.
The commit hash of the genesis block is the
**unique identifier of the chain**.

### Structure

```lua
return {
    version = {0, 11, 0},      -- protocol version
    type    = '#',              -- '#' | '$' | '@' | '@!'
    pioneers = {                -- public ('#') only
        "ed25519:abc...",
        "ed25519:xyz...",
    },
    -- shared = "x25519:def...",     -- private ('$') only
    -- key    = "ed25519:abc...",    -- personal ('@'/'@!') only
}
```

### Fields

#### `version`

Array of three integers `{major, minor, patch}` identifying the
protocol version.
Two peers must share the same major version to synchronize.

#### `type`

A character string defining the access policy of the chain.
It is **immutable** — it cannot change without creating a new
chain.

| Char  | Type                    |
|-------|-------------------------|
| `'#'` | public                  |
| `'$'` | private                 |
| `'@'` | personal (read-only)    |
| `'@!'`| personal (writeable)    |

See [Chains](chains.md) for details on each type.

#### `pioneers`

A list of Ed25519 public keys with elevated initial reputation.
Only relevant for public (`'#'`) chains.
Optional — a chain with no pioneers is fully open.

#### `shared`

An X25519 shared key for encrypted communication.
Only relevant for private (`'$'`) chains.

#### `key`

An Ed25519 public key identifying the chain owner.
Only relevant for personal (`'@'` / `'@!'`) chains.

### Free-form table

The genesis table is free-form: any extra fields beyond `version`,
`type`, and the type-specific key are accepted and become part of
the commit message (and thus part of the chain identity hash).
Applications may use extra fields for metadata, namespaces, or
configuration.

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
- To join an existing chain, use `chains add --clone`

### Git Mapping

The genesis block corresponds to the **first commit** of a bare
git repository.
The commit uses real values for author/committer fields:

| Field            | Value                                        |
|------------------|----------------------------------------------|
| tree             | empty tree (`git hash-object -t tree /dev/null`) |
| parent           | none                                         |
| author name      | `<ed25519 pubkey>`                           |
| author email     | `freechains`                                 |
| author date      | current timestamp                            |
| committer name   | `<ed25519 pubkey>`                           |
| committer email  | `freechains`                                 |
| committer date   | current timestamp                            |
| message          | canonical serialization of all genesis fields|

Two calls with the same parameters produce **different** commit
hashes (different timestamps), creating distinct chains.

---

## Key Design Decisions

### Hash = identity

```
genesis_hash = git_commit_hash(genesis)
```

Each genesis commit is unique because it includes real timestamps
and the creator's public key.
All genesis fields (version, type, pioneers/shared/key, and any
extra fields) are part of the commit message and thus part of
the hash.

### Canonical serialization

The commit message is a canonical Lua-style literal of all
genesis fields:
- Keys sorted alphabetically at each level
- Pioneer lists sorted for consistency
- `nil` values omitted

Examples:
```
{type="#",version={0,11,0}}
{pioneers={"ed25519:abc","ed25519:xyz"},type="#",version={0,11,0}}
{shared="x25519:def123",type="$",version={0,11,0}}
{key="ed25519:mypub",type="@",version={0,11,0}}
{key="ed25519:mypub",type="@!",version={0,11,0}}
```

### Git mapping

Genesis = first commit of a bare repo, with real values:

| Field            | Value                                        |
|------------------|----------------------------------------------|
| tree             | empty tree                                   |
| parent           | none                                         |
| author name      | `<ed25519 pubkey>`                           |
| author email     | `freechains`                                 |
| author date      | current timestamp                            |
| committer name   | `<ed25519 pubkey>`                           |
| committer email  | `freechains`                                 |
| committer date   | current timestamp                            |
| message          | canonical serialization of all genesis fields|

Each creation produces a unique commit hash.
To join an existing chain, use `chains add --clone`.

## Test Coverage

| #     | What                                       | Assertions |
|-------|--------------------------------------------|------------|
| 1–2   | Basic creation (commit type, HEAD)         | 2          |
| 3     | No parent                                  | 1          |
| 4     | Empty tree                                 | 1          |
| 5–6   | Author/committer name = pubkey             | 2          |
| 7–8   | Author/committer email = "freechains"      | 2          |
| 9     | Dates = real timestamps (non-zero)         | 1          |
| 10    | Message = canonical serialization          | 1          |
| 11    | Uniqueness: same params → different hash   | 1          |
| 12    | Different version → different message      | 1          |
| 13    | Different type char → different message    | 1          |
| 14–16 | Public chain with pioneers (sorted)        | 3          |
| 17–18 | Private chain with shared key              | 2          |
| 19–20 | Personal '@' vs '@!' different messages    | 2          |
| 21    | Chain ID = commit hash, valid hex          | 1          |
| **Total** |                                        | **22**     |
