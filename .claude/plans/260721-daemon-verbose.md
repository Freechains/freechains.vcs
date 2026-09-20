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

## Landed: the `--informative-errors` half of option 3

`daemon start` now always passes `--informative-errors`
(`src/freechains/daemon.lua`).
It was the half that cost nothing: `--export-all` already answers
"does this chain exist?" to any fetch, so naming the reason leaks
nothing the daemon did not already give away.

What it fixes, reported from a fresh peer:

```
$ freechains daemon start
Serving on port 8330...
[14960] 'receive-pack': service not enabled for '.../chains//#p2p'
```

The daemon logged that (git logs refusals by default), while the
SENDER got `access denied or repository not exported`, which reads as
a missing chain and never mentions `--hub`.
`sync send` now maps the reasons to our own errors
(`src/freechains/chain/sync.lua`):

| git says (informative)   | freechains says                        |
|--------------------------|----------------------------------------|
| `service not enabled`    | `remote refused push : daemon without --hub` |
| `no such repository`     | `remote refused push : no such chain`  |
| (neither: an older peer) | `... : no such chain, or daemon without --hub` |

Also fixed with it: `cli.md` hung "the remote daemon must run with
`--hub`" under `recv`, where it is false -- `recv` only fetches.
It is a `send` requirement.

## Pending

- [x] Confirm `--` already forwards flags to `git daemon`
- [x] NEXT: pick option 1, 2 or 3 -- option 3
- [x] Implement `--informative-errors` (+ the `sync send` mapping)
- [ ] NEXT: `--verbose`, still only reachable as
      `daemon start -- --verbose`
    - option 3 wanted it behind a `freechains` flag
    - undecided: new CLI surface for what `--` already exposes
- [ ] Check `--log-destination=stderr` is supported by the local git
      (added in git 2.16)
- [x] Update `README.md` if the printed output changes -- output
      unchanged; `### Synchronization` now says a plain daemon serves
      clones and `recv` only
