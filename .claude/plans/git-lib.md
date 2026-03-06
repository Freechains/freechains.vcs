# Plan: Migrate shell git commands to luagit2 library

## Context

`src/freechains` shells out to `git` for all repository operations.
Replace these with [libgit2/luagit2](https://github.com/libgit2/luagit2)
(`lua-git2` on luarocks) to remove the subprocess overhead and
gain programmatic control over git objects.

## Library choice

| Library             | Stars | Last update | Lua 5.4 | Luarocks   |
|---------------------|-------|-------------|---------|------------|
| libgit2/luagit2     | 171   | Oct 2024    | unclear | `lua-git2` |
| SatyendraBanjare/.. | 16    | older       | 5.3     | yes        |
| luapower/libgit2    | —     | older       | LuaJIT  | no         |

**Pick: libgit2/luagit2** — official, most maintained, on luarocks.

## Spike results

### Lua 5.4 compatibility: CONFIRMED

- `lua-git2 0.1-1` installs and loads under Lua 5.4.
- Requires `libgit2-dev` system package.
- `Repository.init`, `is_bare()`, `path()` all work.

### API audit: binding is minimal

Introspection of the installed binding revealed limited coverage.

**Available classes:**
`ODB`, `ODBBackend`, `OdbObject`, `Repository`, `Commit`, `Tree`,
`TreeEntry`, `Blob`, `Tag`, `Reference`, `RevWalk`, `Index`,
`IndexEntry`, `IndexEntryUnmerged`, `Config`, `Signature`, `OID`,
`OID_Shorten`, `StrArray`, `Object`

**Repository instance methods:**
`head`, `is_bare`, `is_empty`, `head_unborn`, `head_detached`,
`path`, `workdir`, `set_workdir`, `index`, `odb`, `set_odb`,
`config`, `set_config`, `set_index`

**Index instance methods:**
`add_bypath`, `add`, `remove`, `write`, `read`, `read_tree`,
`clear`, `find`, `entrycount`, `get_bypath`, `get_byindex`,
`reuc_get_bypath`, `reuc_get_byindex`, `reuc_entrycount`

**ODB class methods:** `new`, `open`, `hash`, `hashfile`
**ODB instance methods:** `write`, `read`, `read_header`,
`read_prefix`, `exists`, `add_backend`, `add_alternate`, `free`

**MISSING (critical for Steps 2–3):**
- `Index:write_tree()` — cannot convert index to tree OID
- `TreeBuilder` — cannot build tree objects programmatically
- `Commit.create` — exists but untested (no tree to pass it)

**AVAILABLE (sufficient for Step 4):**
- `ODB.hash(data, type)` — direct replacement for
  `git hash-object --stdin`

### Options for Steps 2–3

1. **Minimal migration** — only replace `hash-object` (Step 4)
   with `ODB.hash`; keep shell for init/add/commit
2. **Raw object approach** — build tree/commit bytes manually
   via `odb:write` (complex, error-prone)
3. **Different library** — find a more complete Lua-git binding

## Command mapping

| Current shell command                   | luagit2 API                   | Status  |
|-----------------------------------------|-------------------------------|---------|
| `git init <path>`                       | `Repository.init(path, 0)`    | works   |
| `git -C <repo> add <file>`             | `idx:add_bypath(f)` + write   | works   |
| `git -C <repo> commit ...`             | blocked (no write_tree)       | blocked |
| `git -C <repo> rev-parse HEAD`         | blocked (no write_tree)       | blocked |
| `printf .. \| git hash-object --stdin` | `ODB.hash(data, "blob")`     | pending |

## Migration steps

### Step 1 — Add dependency

- Add `lua-git2` to project dependencies / CI install.
- Require at top of `src/freechains`:
  ```lua
  local git2 = require("git2")
  ```

### Step 2 — `chains add` (init + add + commit)

Replace lines 128–135 in `src/freechains`:

```lua
-- current
exec("git init " .. tmp)
exec("cp " .. args.path .. " " .. tmp .. "/.genesis.lua")
exec("git -C " .. tmp .. " add .genesis.lua")
exec("git -C " .. tmp
    .. ' -c user.name="-" -c user.email="-"'
    .. ' commit --allow-empty-message -m ""')
local hash = exec("git -C " .. tmp .. " rev-parse HEAD")
```

With:

```lua
local repo = git2.Repository.init(tmp, 0)
-- cp genesis file (still use os/io)
local idx = repo:index()
idx:add_bypath(".genesis.lua")
idx:write()
local tree_oid = idx:write_tree()    -- if available
local tree = repo:lookup(tree_oid)   -- or build tree
local sig = git2.Signature.new("-", "-", os.time(), 0)
local oid = git2.Commit.create(
    nil, repo, "HEAD", sig, sig, nil, "", tree
)
local hash = tostring(oid)
```

Note: `Commit.create` parent list needs verification — genesis
has no parents.

### Step 3 — `chain post` (add + commit)

Replace lines 196–200:

```lua
-- current
exec("git -C " .. repo .. " add " .. name)
exec("git -C " .. repo
    .. ' -c user.name="-" -c user.email="-"'
    .. ' commit --allow-empty-message -m ""')
local hash = exec("git -C " .. repo .. " rev-parse HEAD")
```

With similar pattern: open repo, index add, commit, get OID.

### Step 4 — `hash-object` for inline posts

Replace line 187:

```lua
-- current
local hash = exec(
    "printf '%s' '" .. args.text .. "' | git hash-object --stdin"
)
```

With:

```lua
local oid = git2.ODB.hash(args.text, "blob")
local hash = tostring(oid)
```

### Step 5 — Non-git shell commands (separate concern)

These remain as shell or get replaced with Lua/lfs:

| Command | Alternative |
|---------|-------------|
| `cp` | `io.open` read/write |
| `rm -rf` | `os.remove` / lfs |
| `ln -s` | keep or lfs |
| `find` | lfs / `io.popen` |
| `readlink` | keep or lfs |

## Risks

- ~~**Lua 5.4 compat**: confirmed working.~~
- **Index:write_tree()**: CONFIRMED MISSING — binding does not
  expose this method.
  Blocks commit creation via the index path.
- **Commit.create signature**: untested — cannot reach this
  step without a tree object.
- **Bare vs non-bare**: chains are bare repos but `chains add`
  currently uses non-bare init.
  Moot until commit creation is unblocked.
- **Binding completeness**: lua-git2 0.1-1 wraps only a subset
  of libgit2.
  Full init/add/commit migration requires either raw object
  construction or a more complete binding.

## Verification

```bash
cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chains.lua
cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chain.lua
```

## Decision: ABANDONED — keep git CLI

The lua-git2 binding (0.1-1) is too incomplete for the core
operations (init/add/commit).
The only feasible replacement is `ODB.hash` for `hash-object`,
which is not worth the added C dependency (`libgit2-dev`).

**Rationale:**
- `Index:write_tree()` and `TreeBuilder` are missing — blocks
  commit creation entirely
- Raw object construction via `odb:write` is complex and fragile
- Git CLI already works, is fully featured, and has no extra deps
- Subprocess overhead is negligible for this use case

**Action items:**
- [x] Revert Step 1 changes (CI + require) — pending

## Status

- [x] Spike: confirm lua-git2 works with Lua 5.4
- [x] Step 1: add dependency (to be reverted)
- [~] Step 2: migrate `chains add` — blocked, abandoned
- [~] Step 3: migrate `chain post` — blocked, abandoned
- [~] Step 4: migrate `hash-object` — feasible but not worth it
- [~] Step 5: evaluate non-git shell commands — separate concern
