# freechains.vcs

[![Tests](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml/badge.svg)](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml)

## Install

Freechains 0.20 (`vcs`) is implemented in Lua on top of Git.

Install dependencies:

```
sudo apt install git openssh-client lua5.4 luarocks
```

Minimum versions:

| Tool         | Version | Why                              |
|--------------|---------|----------------------------------|
| `git`        | >= 2.35 | `gpg.format=ssh` commit signing  |
| `ssh-keygen` | >= 8.2  | `-Y sign` / `-Y verify`          |
| `lua`        | >= 5.4  | runtime                          |

Install via LuaRocks:

```
sudo luarocks install freechains
```

This installs the `freechains` command to `/usr/local/bin/`.

## Basics

The basic API of Freechains is straightforward:

- `freechains chains add ...`:         creates or clones a chain locally
- `freechains chain post ...`:         posts to a chain (signed with SSH)
- `freechains chain like/dislike ...`: rates a post
- `freechains chain order`:            shows posts in consensus order
- `freechains chain reps ...`:         queries reputation
- `freechains chain sync send/recv`:   synchronizes with a remote peer

All application data resides in `~/.freechains/`, overridable with
`--root <dir>`.

A step-by-step example follows.

- Create an SSH keypair:

```
$ ssh-keygen -t ed25519
```

The keypair in `~/.ssh/id_ed25519*` becomes your identity, and is applied to
all signed commits.
