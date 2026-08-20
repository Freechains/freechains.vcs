# `chains add init --pioneer`

- Replace the two `init` forms by one, taking pioneers directly
- `init file <path>` and `init inline --sign=<key>` both go away
- Possible: yes, the change is small and the tests map 1-to-1

# Goal

```
freechains chains add <alias> init [--pioneer=<key>]...
```

- `--pioneer` repeats, once per pioneer
- `<key>` in either format
    - a key FILE, private or public
    - a full key STRING, `ssh-ed25519 AAAA...`
- no `--pioneer` at all: chain with no pioneers, nobody holds reps
- `--pioneer` with no value: `$HOME/.ssh/id_ed25519`
    - same default `--sign` has today

# Resolution rule

- Existence first, so a file named `ssh-x` is never ambiguous
- `io.open(v)` opens: it is a FILE
    - first line starts with `ssh-`: public key file, take it
    - else: private key, `ssh-keygen -y -f <v>`
- else starts with `ssh-`: literal key STRING
- else: `ERROR : chains add : invalid pioneer : <v>`
- Normalize with the `^(%S+ %S+)` match already in `chains.lua`
    - drops the trailing comment
- Dedup before the `reps.max // #pioneers` split
    - a repeated key would silently halve every share

# What happens to genesis files

- The chain's own `chains/<id>/genesis.lua` STAYS
    - it is the content of the genesis commit
    - it is now ALWAYS generated, never user-supplied
- The test fixtures `tst/genesis-{0..4}.lua` GO
- Generated fields, as `init inline` does today
    - `version`: the running `VERSION`
    - `type`: `"#"`
    - `name`: the `<alias>`
    - `pioneers`: the resolved keys
- LOST: no way to set `name`, `descr`, `type`, `version`
    - `descr` is stored but never read by the code
    - see open questions

# Steps

## 1. parser (`src/freechains.lua`)

- Drop `cmd.chains.add.init.file` and `.inline`
- `init` becomes a leaf command
- `:option("--pioneer"):args("?"):count("*")`
    - the `sign` action already resolves a missing value
- `--sign` disappears from `chains add`
    - it never signed anything there

## 2. `src/freechains/chains.lua`

- Drop the `ARGS.file or ARGS.inline` branch (~20 lines)
- Drop the `loadfile(ARGS.path)` validation
    - `invalid genesis` becomes unreachable, remove it
- Build the table from the resolved `--pioneer` list
- Keep `cp genesis.lua` writing the GENERATED file
- Keep the `too many pioneers` check untouched

## 3. tests

- Mechanical for 40+ files: `init file ` -> `init `
- `tst/tests.lua`: `GEN_N` stop being paths, become flags
    - `GEN_0 = ""`
    - `GEN_1 = "--pioneer=" .. PUB1`
    - `GEN_2 = GEN_1 .. " --pioneer=" .. PUB2`, and so on
    - call sites keep reading `.. GEN_2`, untouched
    - quote the values: keys carry a space
- Delete `tst/genesis-{0..4}.lua`
- `tst/trash/bug-forged-state.lua` too, if still run

## 4. docs

- `cli.md`: usage block, `chains add` section, examples
- `README.md:108`: the `init inline --sign=` line
- `guide.sh:58`: same line
- `.claude/plans/commands.md`, `genesis.md`: check for the forms

# Tests needing real work, all in `cli-chains.lua`

- `genesis file` (l.20): no `diff` against a fixture any more
    - assert the GENERATED fields instead
    - `name` is now `#cli-chains`, not `A forum`
    - `version` is now `{0,20,0}`, not `{1,2,3}`
- `bad genesis file` (l.83), `genesis file not found` (l.97)
    - the error is gone: replace by `invalid pioneer` cases
- `init missing subcommand` (l.105), `init invalid` (l.114)
    - `init` takes no subcommand: now an argparse error
    - re-anchor on whatever argparse prints
- `inline creates chain` (l.259) -> `init --pioneer=<file>`
- `inline uses default --sign` (l.283) -> bare `--pioneer`
- `inline with bad --sign` (l.300)
    - today it carries ssh-keygen's own detail
    - `/nonexistent/key` now fails the existence test first
    - keep the ssh-keygen detail only for a file that EXISTS
      and is not a key
- pioneer limit (l.317, l.340): 101 and 100 fake keys
    - they were written to a temp genesis file
    - now 101 `--pioneer='ssh-ed25519 111...'` flags
    - ~6 KB of argv, far under any limit

# Open questions

- Is losing `descr` acceptable?
    - never read, only carried in the commit
    - if it must stay: `--descr=<text>`, one more option
- Is losing a human `name` acceptable?
    - `name` becomes the alias, always
    - the alias is local, so peers may disagree on it
- Should `init` with no `--pioneer` be legal?
    - it is legal today via a fixture with no `pioneers`
    - a chain nobody can post to, until someone is liked
    - keep it: the tests use it (`GEN_0`) and it costs nothing
- Public key files: accept a `.pub` with a comment?
    - yes, the `%S+ %S+` match already drops it

# Won't do

- No `--pioneer` for `chains add clone`: pioneers come with the
  cloned genesis
- No back-compat alias for `init file`: pre-release, no users
