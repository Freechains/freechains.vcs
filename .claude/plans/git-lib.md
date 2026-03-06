# Plan: Migrate shell git commands to luagit2 library

## Context

`src/freechains` shells out to `git` for all repository operations.
Replace these with [libgit2/luagit2](https://github.com/libgit2/luagit2)
(`lua-git2` on luarocks) to remove the subprocess overhead and
gain programmatic control over git objects.

## Library choice

| Library | Stars | Last update | Lua 5.4 | Luarocks |
|---------|-------|-------------|---------|----------|
| libgit2/luagit2 | 171 | Oct 2024 | unclear | `lua-git2` |
| SatyendraBanjare/luagit2 | 16 | older | 5.3 only | yes |
| luapower/libgit2 | — | older | LuaJIT | no |

**Pick: libgit2/luagit2** — official, most maintained, on luarocks.

## Command mapping

| Current shell command | luagit2 API |
|-----------------------------------------|----------------------------------------------|
| `git init <path>` | `Repository.init(path, 1)` |
| `git -C <repo> add <file>` | `repo:index():add_bypath(f)` + `idx:write()` |
| `git -C <repo> commit ...` | `Commit.create(oid, repo, ref, author, ...)` |
| `git -C <repo> rev-parse HEAD` | `repo:head():target()` (returns OID) |
| `printf ... \| git hash-object --stdin` | `ODB.hash(data, "blob")` |

## Pre-requisite: spike

Before full migration, confirm Lua 5.4 compatibility:

1. Install: `luarocks install lua-git2`
2. Test script:
   ```lua
   local git2 = require("git2")
   local repo = git2.Repository.init("/tmp/test-luagit2", 1)
   print(repo:is_bare())
   print(repo:path())
   ```
3. If it fails to build/load under 5.4, evaluate patching or
   pinning Lua 5.3.

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

- **Lua 5.4 compat**: C binding may need rebuild or patches.
- **Index:write_tree()**: not visible in docs — may need
  alternative approach to build tree OID.
- **Commit.create signature**: more verbose than shell; parent
  list handling for genesis (no parents) vs posts (1 parent)
  needs testing.
- **Bare vs non-bare**: chains are bare repos but `chains add`
  currently uses non-bare init (working tree needed for
  add/commit).
  Migration may need to handle this differently with
  libgit2's bare repo + manual tree/blob creation.

## Verification

```bash
cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chains.lua
cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chain.lua
```

## Status

- [ ] Spike: confirm lua-git2 works with Lua 5.4
- [ ] Step 1: add dependency
- [ ] Step 2: migrate `chains add`
- [ ] Step 3: migrate `chain post`
- [ ] Step 4: migrate `hash-object`
- [ ] Step 5: evaluate non-git shell commands
