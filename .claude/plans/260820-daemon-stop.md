# `daemon start` / `daemon stop`

- Split `daemon` into two subcommands, add a way to stop one
- `git daemon` already has `--detach` and `--pid-file`
- So Freechains passes them through and reads the pid back

# Goal

```
freechains daemon start [--port=<port>] [--hub] [--detach]
                        [-- <git-daemon-opt>...]
freechains daemon stop  [--port=<port>]
```

- `start` keeps today's behaviour: foreground, blocks
- `--detach`: write the pid file and return
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
- `--detach` without `--pid-file` is refused by us: a
  detached daemon with no pid is exactly what `stop` cannot
  reach

# `stop`, step by step

- Read `<root>/daemon-<port>.pid`
    - missing: `ERROR : daemon stop : not running`
- Verify BEFORE killing: `/proc/<pid>/cmdline` must contain
  `base-path=<root>/chains/`
    - a stale pid may belong to something else entirely
    - mismatch: `ERROR : daemon stop : stale pid file`
      and remove the file
- `kill <pid>`, then remove the file

# What changes

## `src/freechains.lua`

- `cmd.daemon` gains two subcommands, `start` and `stop`
- `--port` moves to both; `--hub` and `xtra` stay on `start`
- `--detach` is a new flag on `start`
- The `if ARGS.daemon` block moves to `src/freechains/daemon.lua`
    - it is the only command still inlined in the parser file

## `src/freechains/daemon.lua` (new)

- `start`: today's `os.execute`, plus `--detach --pid-file`
  when asked
- `stop`: the steps above

## docs

- `cli.md`: usage block and the `daemon` section
- `README.md`: the two `freechains daemon` invocations
- `guide.sh:83,174`: `daemon` -> `daemon start`
    - and the `pkill` block becomes two `daemon stop` calls

# Decided

- `start` stays FOREGROUND by default
    - `&` is the idiom, and tests already rely on it
    - `--detach` is opt-in, and only it writes a pid file
- `stop` takes `--port`, not a pid: the port is what the
  user typed, the pid is an implementation detail
- No `daemon status`: `stop`'s verify step is the same
  check, and nothing needs it yet

# Won't do

- No back-compat bare `daemon`: pre-release, no users
- No pid file for a foreground `start`: the shell owns it
- No `--pid-file=<path>` option: the path is derived, so
  `stop` can always find it
