# Typed chain identifiers

## Purpose

Today the chain genesis hash is bare 40-hex.
Make it typed: `#<40-hex>` (41 chars), so chain identifiers everywhere
carry their type marker — aligning hashes with the existing alias
convention (`#sports`, `#chat`).

Only `#` (public forum) is implemented today ([[chains]]).
`$` and `@`/`@!` are reserved but not yet shipped, so this plan
hardcodes `#`.
The same pattern will extend when other types land
(read `.freechains/genesis.lua`, use `T.type`).

## Why

- Aliases already use the `#` prefix; hashes were the exception.
- Unified shape lets a single check (`raw:find("#")`) say
  "this is a chain id" — needed by [[06-02-url]]'s URL helper.
- Type info is visible in the path/URL without reading the genesis.

## Convention

```
chain id  = #<40-hex>             (41 chars)
chains/
    #<40-hex>/                    typed-hex dir
    <alias> -> #<40-hex>/         alias symlink (target = typed dir)
```

The alias name itself is unchanged in this plan — `chains add x init ...`
still creates `chains/x` as the symlink name.
Auto-prefixing the alias is left for [[chains]] (see Open questions).

## CLI surface

`freechains chains add ... init|clone` prints `#<40-hex>` (was `<40-hex>`).

## Spec updates

| file       | place              | change                                          |
|------------|--------------------|-------------------------------------------------|
| chains.md  | Identification     | identifier = `#<40-hex>`; document `#` prefix   |
| layout.md  | chains/ filesystem | `chains/#<hex>/` (was `chains/<hex>/`)          |

## Code updates

| file       | place         | change                                                          |
|------------|---------------|-----------------------------------------------------------------|
| chains.lua | init 114-128  | `hash = "#" .. rev-parse HEAD`; rename target + symlink target + print |
| chains.lua | clone 144-156 | `hash = "#" .. rev-list --max-parents=0 HEAD`; rename + symlink + print |

`chain/common.lua` (`REPO`) is unchanged — the alias symlink resolves
transparently and nothing downstream of `REPO` knows the underlying
dir name.

## Steps (resume here)

Status: **done** — all tests pass.

Quoting note discovered during implementation: `#` is the shell
comment marker, so every interpolation of a `#`-containing path
into a shell command must be single-quoted.
Spots touched: `chains.lua` (init/clone/rem), `chain/sync.lua`
(push `-o url=...`), `hooks/pre-receive` (spawned `freechains`
command), `tst/cli-chains.lua` (`realpath`).

### Step 1 — `chains.lua` init — DONE

Replace the hash line with the typed form, then reuse `hash`
unchanged for the rename target, symlink target, and `print`:

```lua
local hash = "#" .. exec("git -C " .. tmp .. " rev-parse HEAD")
local final = DIR .. "/" .. hash
if not os.rename(tmp, final) then
    exec("rm -rf " .. tmp)
    ERROR("chains add : init failed")
end
exec("git -C " .. final .. " config freechains.url " .. final)
exec("ln -s " .. hash .. "/ " .. DIR .. "/" .. ARGS.alias)
print(hash)
```

### Step 2 — `chains.lua` clone — DONE

Same pattern for the clone branch:

```lua
local hash = "#" .. exec (
    "git -C " .. tmp .. " rev-list --max-parents=0 HEAD"
)
local dir = DIR .. "/" .. hash .. "/"
if not os.rename(tmp, dir) then
    exec("rm -rf " .. tmp)
    ERROR("chains add : clone failed")
end
exec("git -C " .. dir .. " config freechains.url " .. dir)
exec("ln -s " .. hash .. " " .. DIR .. "/" .. ARGS.alias)
print(hash)
```

### Step 3 — spec docs — DONE

`chains.md` Identification + Sync example + Layout sample updated.
`layout.md` `<chain-hash>` -> `<chain-id>` everywhere.

### Step 4 — verify — DONE

All tests pass after the quoting fixes above.

## Open questions

- **Alias prefix** — `chains add x init ...` still produces
  `chains/x` (verbatim alias).
  Should `chains add` reject aliases without `#`, or auto-prefix?
  Out of scope here; address when adding other types ([[chains]]).
- **Genesis-driven type** — once `$`/`@` land, read
  `.freechains/genesis.lua` in the tmp dir and use `T.type`
  instead of hardcoded `#`.
  Trivial change.

## Related

- [[chains]] — chain types and identification (the convention this aligns with)
- [[layout]] — filesystem
- [[06-02-url]] — depends on `#` being a universal chain-id marker
