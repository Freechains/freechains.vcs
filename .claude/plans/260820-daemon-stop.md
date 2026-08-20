# `daemon start` / `daemon stop`

- Split `daemon` into two subcommands, add a way to stop one
- `git daemon` already has `--detach` and `--pid-file`
- So Freechains passes them through and reads the pid back

# Goal

```
freechains daemon start [--port=<port>] [--hub]
                        [-- <git-daemon-opt>...]
freechains daemon stop  [--port=<port>]
```

- `start` keeps today's behaviour: foreground, blocks
- `stop`: read the pid, kill it, remove the file

# Why

- `guide.sh:39-41` kills leftovers with
  `pkill -f "base-path=$BASE"`
    - it even documents the trap: the listener is
      `git-daemon` (hyphen), not `git daemon`
- Scripts cannot tell which daemon they started
- The README walkthrough leaves two daemons running
- v0.8 had `freechains-host start | stop`, so the shape is
  not new

# Pid file

- Path: `<root>/daemon-<port>.pid`
- One daemon per root and port, so the name is the key
- `git daemon --pid-file=<path>` writes it, we never do
- It is written even in the foreground, so `stop` reaches a
  `start` backgrounded with `&`
- MEASURED: `--detach` is NOT needed for that, so the flag
  was dropped

# `stop`, step by step

- Read `<root>/daemon-<port>.pid`
    - missing: `ERROR : daemon stop : not running`
- Remove the file, then `kill <pid>`
    - a dead pid fails the kill: same `not running`
- DECIDED: no pid-reuse guard
    - reading `/proc/<pid>/cmdline` to confirm it is really
      our daemon was dropped as over-protection
    - it also made `stop` Linux-only

# What changes

## `src/freechains.lua`

- `cmd.daemon` gains two subcommands, `start` and `stop`
- `--port` moves to both; `--hub` and `xtra` stay on `start`
- The `if ARGS.daemon` block moves to `src/freechains/daemon.lua`
    - it is the only command still inlined in the parser file

## `src/freechains/daemon.lua` (new)

- `start`: today's `os.execute`, plus `--pid-file`
- a signal is not a failure: `stop` kills `start`
- `stop`: the steps above

## docs

- `cli.md`: usage block and the `daemon` section
- `README.md`: the two `freechains daemon` invocations
- `guide.sh:83,174`: `daemon` -> `daemon start`
    - and the `pkill` block becomes two `daemon stop` calls

# Decided

- `start` stays FOREGROUND, with no way to detach
    - `&` is the idiom, and tests already rely on it
- `stop` takes `--port`, not a pid: the port is what the
  user typed, the pid is an implementation detail
- No `daemon status`: `stop`'s verify step is the same
  check, and nothing needs it yet

# Won't do

- No back-compat bare `daemon`: pre-release, no users
- No pid file for a foreground `start`: the shell owns it
- No `--pid-file=<path>` option: the path is derived, so
  `stop` can always find it
