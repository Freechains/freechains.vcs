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
