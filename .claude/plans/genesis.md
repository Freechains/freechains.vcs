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

The genesis block corresponds to the **first commit** of a git
repository.
Author/committer are left blank (no signing yet).
The genesis data lives in a `.genesis.lua` blob in the tree.

| Field            | Value                                        |
|------------------|----------------------------------------------|
| tree             | tree with `.genesis.lua` blob                |
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
All genesis fields live in the `.genesis.lua` blob inside the
commit tree and are thus part of the hash.

## Test Coverage

| #     | What                                       | Assertions |
|-------|--------------------------------------------|------------|
| 1–2   | Basic creation (commit type, HEAD)         | 2          |
| 3     | No parent                                  | 1          |
| 4     | Tree contains `.genesis.lua`               | 1          |
| 5–6   | Author/committer name = blank              | 2          |
| 7–8   | Author/committer email = blank             | 2          |
| 9     | Message = empty                            | 1          |
| 10    | Uniqueness: same params → different hash   | 1          |
| 11    | `.genesis.lua` content matches input file  | 1          |
| 12    | Chain ID = commit hash, valid hex          | 1          |
| 13    | Symlink alias → hash directory             | 1          |
| **Total** |                                        | **13**     |
