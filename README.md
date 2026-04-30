# freechains.vcs

[![Tests](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml/badge.svg)](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml)

## Install

Freechains is implemented in Lua on top of Git.

Install dependencies:

```
sudo apt install git openssh-client lua5.4 luarocks
```

Install via LuaRocks:

```
sudo luarocks install freechains
```

Verify that `freechains` is installed:

```
which freechains
```

## Basics

The basic API of Freechains is straightforward:

- `freechains chains add ...`:         creates or clones a chain locally
- `freechains chain post ...`:         posts to a chain (signed with SSH)
- `freechains chain like/dislike ...`: rates a post
- `freechains chain order`:            shows posts in consensus order
- `freechains chain reps ...`:         queries reputation
- `freechains chain sync send/recv`:   synchronizes with a remote peer

Follows a step-by-step execution:

- Create an SSH keypair:

```
ssh-keygen -t ed25519
```

The keypair in `~/.ssh/*` becomes your default identity:

```
ls ~/.ssh/id_ed25519*
```

- Create a chain locally:

```
freechains chains add '#chat' init inline --sign
461cfb4...
```

This creates the public chain `#chat`, with you as the sole pioneer.
The output is the chain's unique identifier across all peers.

All application data resides in `~/.freechains/`:

```
ls ~/.freechains/chains/
```
