# Plan: Implement `freechains` CLI in Lua

## Context

Lua CLI for Freechains VCS.
First pass: `chains add/rem/list` subcommands.

## Scope

- `freechains chains add <alias> args [--flags]`
- `freechains chains add <alias> lua <file>`
- `freechains chains add <alias> remote <host> <hash-or-alias>`
- `freechains chains rem <alias>`
- `freechains chains list`
- Global option: `--root` (default `~/.freechains/`)

## Files

```
src/
  freechains       executable Lua script (entry point + all logic)
  argparse.lua     vendored from luarocks/argparse (MIT)
Makefile           curl argparse + install to /usr/local/bin/
```

## Makefile

```makefile
all: src/argparse.lua

src/argparse.lua:
	curl -sL -o $@ \
	  https://raw.githubusercontent.com/luarocks/argparse/\
0.7.1/src/argparse.lua

install: src/argparse.lua
	install -m 755 src/freechains /usr/local/bin/freechains
	install -m 644 src/argparse.lua \
	  /usr/local/share/lua/5.4/

clean:
	rm -f src/argparse.lua
```

## CLI API

### Global option

```
freechains --root <dir> chains ...
```

Default: `~/.freechains/`.

### Type characters

| Char  | Type                    | Required flag    |
|-------|-------------------------|------------------|
| `'#'` | public                  | `--pioneers`     |
| `'$'` | private                 | `--shared`       |
| `'@'` | personal (read-only)    | `--key`          |
| `'@!'`| personal (writeable)    | `--key`          |

### `chains add <alias> args`

Create a new chain from CLI flags.

**Prefix inference**: if alias starts with `#`, `$`, `@!`, or
`@`, the type is inferred and `--type` is not needed.

**Explicit type**: if alias has no prefix, `--type <char>` is
required.

```bash
# prefix inference
freechains chains add '#sports' args \
    --pioneers ed25519:k1,ed25519:k2
freechains chains add '$family' args \
    --shared x25519:key
freechains chains add '@me' args \
    --key ed25519:pubkey
freechains chains add '@!feedback' args \
    --key ed25519:pubkey

# explicit type
freechains chains add mytopic args \
    --type '#' --pioneers ed25519:k1
```

At least one key-related flag is required (no bare type-only
creation).

### `chains add <alias> lua <file>`

Create a new chain from a Lua genesis file.
The file must return a genesis table:

```lua
return {
    version  = {0, 11, 0},
    type     = '#',
    pioneers = {"ed25519:abc", "ed25519:xyz"},
}
```

```bash
freechains chains add mychain lua genesis.lua
```

### `chains add <alias> remote <host> <hash-or-alias>`

Clone an existing chain from a peer.
The third argument can be a genesis hash or an alias on the
remote host.

```bash
freechains chains add '#sports' remote peer1:8330 A95B969D...
freechains chains add '#sports' remote peer1:8330 '#sports'
```

### `chains rem <alias>`

Delete a chain: removes both the symlink and the bare git repo.

```bash
freechains chains rem '#sports'
```

### `chains list`

List all chain aliases (symlinks in `<root>/chains/`).

```bash
freechains chains list
```

## Design: `src/freechains`

Single Lua script with:

- argparse setup: `--root`, `chains` command with `add`,
  `rem`, `list` subcommands
- `add` has sub-modes: `args`, `lua`, `remote`

### `chains add` (args / lua)

1. Read Lua file, `dofile` to validate it returns a table
2. `mkdir <tmp> && git -C <tmp> init`
3. `cp <file> <tmp>/.genesis.lua`
4. `git -C <tmp> add .genesis.lua`
5. `git -C <tmp> -c user.name="" -c user.email=""`
   `commit --allow-empty-message -m ""`
6. `git -C <tmp> rev-parse HEAD` → hash
7. `mv <tmp> <root>/chains/<hash>/`
8. `ln -s <hash>/ <root>/chains/<alias>`
9. Print hash to stdout

### `chains add` (remote)

1. `git clone --bare <host>/<hash-or-alias> <root>/chains/<tmp>/`
2. Read genesis hash from `git rev-list --max-parents=0 HEAD`
3. Rename repo dir to `<root>/chains/<hash>/`
4. Create symlink `<root>/chains/<alias> -> <hash>/`
5. Print hash to stdout

### `chains rem`

1. Resolve symlink target
2. `rm -rf` the bare repo
3. Remove the symlink

### `chains list`

1. Iterate symlinks in `<root>/chains/`
2. Print each alias and its target hash

## Verification

```bash
make
sudo make install

# args mode — prefix inference
freechains chains add '#sports' args \
    --pioneers ed25519:k1,ed25519:k2
freechains chains add '$family' args \
    --shared x25519:def
freechains chains add '@me' args \
    --key ed25519:pub
freechains chains add '@!feedback' args \
    --key ed25519:pub

# args mode — explicit type
freechains chains add mytopic args \
    --type '#' --pioneers ed25519:k1

# lua mode
freechains chains add mychain lua genesis.lua

# list and remove
freechains chains list
freechains chains rem '#sports'
freechains chains list
```

## Progress

- [ ] Create `Makefile`
- [ ] Create `src/freechains` (entry point + all logic)
- [ ] Download `argparse.lua`
- [ ] Test manually
