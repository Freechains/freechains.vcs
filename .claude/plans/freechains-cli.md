# Plan: Implement `freechains` CLI in Lua

## Context

Lua CLI for Freechains VCS.
Subcommands: `chains add/rem/list`, `chain post`.

## Scope

- `freechains chains add <alias> args [--flags]`
- `freechains chains add <alias> lua <file>`
- `freechains chains add <alias> remote <host> <hash-or-alias>`
- `freechains chains rem <alias>`
- `freechains chains list`
- `freechains chain <alias> post file <path>`
- `freechains chain <alias> post inline <text> [--file <name>]`
- Global option: `--root` (default `~/.freechains/`)

## Files

```
src/
  freechains       executable Lua script (entry point + all logic)
  argparse.lua     vendored from luarocks/argparse (MIT)
Makefile           curl argparse + install to /usr/local/bin/
tst/
  cli-chains.lua   tests for chains add/rem/list
  cli-chain.lua    tests for chain post
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
Output: one alias per line, sorted.

```bash
freechains chains list
```

### `chain <alias> post file <path>`

Post a file.
Uses the file's basename in the tree.

```bash
freechains chain mychain post file hello.txt
freechains chain mychain post file photo.jpg
```

### `chain <alias> post inline <text> [--file <name>]`

Post inline text.
Text always ends with `\n` (appended if missing).

- `--file foo.txt` → appends to `foo.txt` (creates if new).
  Ensures a leading `\n` if the file doesn't end with one.
- No `--file` → auto-generates: `<timestamp>-<hash8>.txt`
  (unix timestamp + first 8 chars of content sha1).
  Always a new file.

```bash
freechains chain mychain post inline "Hello"
# creates 1741192800-a3b2c1d4.txt with "Hello\n"

freechains chain mychain post inline "Line 1" --file log.txt
# creates log.txt with "Line 1\n"

freechains chain mychain post inline "Line 2" --file log.txt
# appends "\nLine 2\n" to log.txt

freechains chain mychain post inline "Second note"
# creates 1741192801-b4c3d2e1.txt (new auto-name)
```

## Design: `src/freechains`

Single Lua script with:

- argparse setup: `--root`, `chains` command with `add`,
  `rem`, `list` subcommands
- `chain` command with `post` subcommand
- `add` has sub-modes: `args`, `lua`, `remote`
- `post` has sub-modes: `file`, `inline`

### `chains add` (args / lua)

1. Read Lua file, `dofile` to validate it returns a table
2. `mkdir <tmp> && git -C <tmp> init`
3. `cp <file> <tmp>/.genesis.lua`
4. `git -C <tmp> add .genesis.lua`
5. `git -C <tmp> -c user.name="-" -c user.email="-"`
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
2. Print each alias (one per line, sorted)

### `chain post`

1. Resolve `<alias>` → chain repo path via symlink
2. Write content to `<repo>/<filename>`
   - file mode: `cp <path> <repo>/<basename>`
   - inline mode (--file): append `\n`+text+`\n` to file
     (create if new; skip leading `\n` on new file)
   - inline mode (no --file): write text+`\n` to auto-named
     file `<timestamp>-<hash8>.txt`
3. `git -C <repo> add <filename>`
4. `git -C <repo> -c user.name="-" -c user.email="-"`
   `commit --allow-empty-message -m ""`
5. `git -C <repo> rev-parse HEAD` → hash
6. Print hash to stdout

## Progress

- [x] Create `Makefile`
- [x] Create `src/freechains` (entry point + all logic)
- [x] Download `argparse.lua`
- [x] `chains add <alias> lua` implemented + tested
- [x] `chains rem <alias>` implemented + tested
- [x] `chains list` implemented + tested
- [ ] `chain <alias> post file` (pending)
- [ ] `chain <alias> post inline` (pending)
- [ ] `chains add <alias> args` (deferred)
- [ ] `chains add <alias> remote` (deferred)
