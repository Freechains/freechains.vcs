# Plan: `freechains daemon` gives no feedback

## Symptom

A running daemon prints one line and then stays mute, whatever
happens:

```
$ freechains daemon
Serving on port 8330...
```

Clones, fetches and pushes leave no trace, so there is no way to tell
a working peer from a wedged one, nor to see which chain was served.

## Current behaviour

`src/freechains.lua:215-225` builds the `git daemon` command with
`--base-path`, `--export-all`, `--enable`, `--port` and whatever the
user appended after `--` (`ARGS.xtra`).
Nothing enables logging, and `git daemon` is quiet by default.

The escape hatch already works today:

```
$ freechains daemon -- --verbose --informative-errors
```

## Proposal

Pass the logging flags from `freechains` itself, so the default
experience is informative.

| flag                     | effect                                   |
|--------------------------|------------------------------------------|
| `--verbose`              | logs each connection and the path served |
| `--informative-errors`   | real reasons to clients, not "access denied" |
| `--log-destination=stderr` | keeps logs in the terminal, not syslog |

Note this covers the transport only.
The hub's own `sync recv` reaches the *sender* as `remote:` lines,
which `sync send` currently swallows (see `260721-send-silent.md`).

## Options

1. Always verbose.
   Matches the intent, one-line change, no new CLI surface.
   Downside: noisy for a long-running public peer.
2. Verbose behind a `--verbose` flag on `freechains daemon`.
   Quiet by default, explicit when wanted, but adds CLI surface for
   something `--` already exposes.
3. Always `--informative-errors`, `--verbose` behind the flag.
   Best default/noise trade-off, slightly more code than option 1.

## Files

| file                | place              | change                        |
|---------------------|--------------------|-------------------------------|
| `src/freechains.lua`| `ARGS.daemon` L215 | add the logging flags         |
| `src/freechains.lua`| parser, L~49       | (options 2 and 3 only)        |
| `README.md`         | `### Synchronization` | daemon output if it changes |

## Pending

- [x] Confirm `--` already forwards flags to `git daemon`
- [ ] NEXT: pick option 1, 2 or 3
- [ ] Implement
- [ ] Check `--log-destination=stderr` is supported by the local git
      (added in git 2.16)
- [ ] Update `README.md` if the printed output changes
