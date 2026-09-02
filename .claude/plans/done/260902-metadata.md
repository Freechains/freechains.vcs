# Metadata in Lua format  [x] DONE

- two commands return machine-readable Lua: `return { ... }`
- loadable by any Lua client: `load(out)()`

# get metadata genesis (new)

- `freechains chain <alias> get metadata genesis`
- NO new verb: `genesis` is a well-known id (`rev-parse`
  finds `refs/genesis` via the ref search path); get.lua
  special-cases it to emit the genesis table
- the chain's constitution: the trust decision before use
  (who owns it: dictators, pioneers, or open)
- no CLI window exists today (`reps authors` shows balances,
  not roles; a dictator at 0 reps is invisible)
- source: `git cat-file commit refs/genesis`, parse as
  `chains.lua genesis()` does
- output:

```
return {
    version   = "0.21.0",
    nonce     = 3004508805,
    dictators = { "ssh-ed25519 AAAA...", ... },
    pioneers  = { "ssh-ed25519 AAAA...", ... },
    open      = false,
}
```

- `open` included: derived, but it IS the question asked

# chain get metadata (adapt)

- today: positional `key value` lines (cli.md template)
- becomes the same Lua shape:

```
return {
    action = "post",
    time   = 1780088002,
    n      = 1000,                  -- votes only
    cid    = "4b2080cf...",         -- vote target (or author)
    blob   = "90c7c77a...",
    sign   = "ssh-ed25519 ...",
    backs  = { "b52c62f...", ... },
}
```

- the cid itself is NOT a field: the caller passed it

# What changes

- `src/freechains/chain/get.lua`: emit the table
- get.lua also owns the genesis case: no argparse change
- `common.lua`: export a table-to-STRING form (today only
  `table_to_file`; the sorter/formatter already exists)
- `doc/cli.md`: both output templates replaced
- callers of `get metadata` output in tst/ adapt

# Decided

- `version`: the string, as the genesis writes it
- genesis `time`: omitted (always 0)
