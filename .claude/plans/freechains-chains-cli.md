# Plan: Implement `freechains` CLI in Lua

## Context

Replacing the Kotlin Freechains CLI with a Lua implementation.
First pass: only `chains join/leave/list` subcommands.

## Scope

- `freechains chains join <name> [keys...]`
- `freechains chains leave <name>`
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
	  https://raw.githubusercontent.com/luarocks/argparse/0.7.1/src/argparse.lua

install: src/argparse.lua
	install -m 755 src/freechains /usr/local/bin/freechains
	install -m 644 src/argparse.lua /usr/local/share/lua/5.4/

clean:
	rm -f src/argparse.lua
```

## Design: `src/freechains`

Single file with:
- argparse setup: `--root`, `chains` command with
  `join/leave/list` subcommands
- `chains join`: `git init --bare` in
  `<root>/chains/<genesis_hash>/`, symlink
  `<root>/chains/<name> → <genesis_hash>/`, create deterministic
  genesis commit (zeroed fields, empty tree, canonical message)
- `chains leave`: resolve symlink, `rm -rf` repo + symlink
- `chains list`: iterate symlinks in `<root>/chains/`

Genesis serialization follows the spec from x1.sh tests:
`{type={keys={...},name="<type>"},version={0,11,0}}`

Chain type inferred from name prefix:
- `#...` → public
- `@...` → personal
- `$...` → private

## Verification

```bash
make
sudo make install
freechains chains join '#test'
freechains chains list
freechains chains leave '#test'
```

## Progress

- [ ] Create `Makefile`
- [ ] Create `src/freechains` (entry point + all logic)
- [ ] Download `argparse.lua`
- [ ] Test manually
