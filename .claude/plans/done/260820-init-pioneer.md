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

- Prefix first: only a key STRING starts with `ssh-`
- `v:match("^ssh%-")`: literal key STRING, take it
- else `<v>` is a PATH
    - opens and first line starts with `ssh-`: public key file
    - else: private key, `ssh-keygen -y -f <v>`
        - its failure is the ONLY error path
        - `invalid pioneer` plus ssh-keygen's own `>>> <<<`
        - a missing file reports `No such file or directory`
- Rejected: existence first
    - `io.open` before the prefix test disambiguates a file
      named `ssh-x`, but swallows ssh-keygen's detail on the
      commonest mistake, a mistyped path
    - the collision needs a BARE relative path named `ssh-*`
    - `./ssh-key` already works, so document it and move on
- Normalize with the `^(%S+ %S+)` match already in `chains.lua`
    - drops the trailing comment
- Dedup before the `reps.max // #pioneers` split
    - a repeated key would silently halve every share

# What happens to genesis files

- The chain's own `chains/<id>/genesis.lua` STAYS
    - it is the content of the genesis commit
    - it is now ALWAYS generated, never user-supplied
- The test fixtures `tst/genesis-{0..4}.lua` GO
- Generated fields, ONLY the two that are read back
    - `version`: the running `VERSION`, the compat hook
    - `pioneers`: the resolved keys
- `type` and `name` are GONE, nothing ever read them
    - `type` returns if `$`/`@` chains land (`260820-cli.md`)
- LOST: no way to set `name`, `descr`, `type`, `version`
    - DECIDED: drop `descr`, the human `name`, and `type`
    - `descr` was stored but never read by the code
    - `name` is the alias, which is local: peers may disagree
    - the chain id stays the only real name

# Steps

- ALL DONE: `make tests` GREEN (39/39), `guide.sh` GREEN
- Plan COMPLETE, ready for `done/`

## 1. parser (`src/freechains.lua`) -- DONE

- Drop `cmd.chains.add.init.file` and `.inline`
- `init` becomes a leaf command
- `:option("--pioneer"):args("?"):count("*")`
    - the `sign` action already resolves a missing value
- `--sign` disappears from `chains add`
    - it never signed anything there

## 2. `src/freechains/chains.lua` -- DONE

- Drop the `ARGS.file or ARGS.inline` branch (~20 lines)
- Drop the `loadfile(ARGS.path)` validation
    - `invalid genesis` becomes unreachable, remove it
- Build the table from the resolved `--pioneer` list
- Write `genesis.lua` in place, the `cp` is gone
- Guard `pioneers()`: `#T.pioneers > 0`, else `// 0` raises
- Keep the `too many pioneers` check untouched

## 3. tests -- DONE

- Mechanical for 40+ files: `init file ` -> `init `
- `tst/tests.lua`: `GEN_N` stop being paths, become flags
    - `GEN_0 = ""`
    - `GEN_1 = "--pioneer=" .. PUB1`
    - `GEN_2 = GEN_1 .. " --pioneer=" .. PUB2`, and so on
    - call sites keep reading `.. GEN_2`, untouched
    - quote the values: keys carry a space
- Delete `tst/genesis-{0..4}.lua`
- `tst/trash/bug-forged-state.lua` too, if still run

## 4. docs -- DONE

- `cli.md`: usage block, `chains add` section, examples
- `README.md:108`: the `init inline --sign=` line
- `guide.sh:58`: same line
- `.claude/plans/commands.md`, `genesis.md`: check for the forms

# Tests needing real work, all in `cli-chains.lua` -- DONE

- Landed as planned, with two deviations
    - `init missing subcommand` is GONE, not re-anchored:
      bare `init` is now the legal zero-pioneer case
    - `pioneer file is not a key` matches the head line only,
      since ssh-keygen's detail is not stable

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
    - prefix-first keeps it: only the head line changes,
      from `invalid sign key` to `invalid pioneer`
- pioneer limit (l.317, l.340): 101 and 100 fake keys
    - they were written to a temp genesis file
    - now 101 `--pioneer='ssh-ed25519 111...'` flags
    - ~6 KB of argv, far under any limit

# Decided

- Drop `descr`: never read, no `--descr` option
- Drop the human `name` and `type`: unread, so unwritten
- `init` with no `--pioneer` stays LEGAL
    - a chain where nobody holds reps
    - the tests already use it (`GEN_0`)
- Errors: prefix first, ssh-keygen keeps reporting the detail
- Public key files keep their comment, `%S+ %S+` drops it

# Found on the way -- CLOSED

- `pioneers()` ran `dofile` on the CLONED `genesis.lua`
    - remote Lua executed locally on `chains add clone`
    - predates this change: the dropped validation was
      only on the `init` path, and `loadfile` runs too
- `chain get payload` had the same shape (`get.lua`)
    - the action file is remote-authored
    - the sandboxed check in `sync` does not protect a
      later call that re-loads the bytes with globals
- FIXED: both use `load(src, "=...", "t", {})`, the shape
  `ACTION.read` already had
    - a non-table genesis is refused as `invalid genesis`
- Recorded as T6c in `threats.md`, matrix row included
- STILL OPEN: `state.lua` `M.read`, see TODO

# Won't do

- No `--pioneer` for `chains add clone`: pioneers come with the
  cloned genesis
- No back-compat alias for `init file`: pre-release, no users
