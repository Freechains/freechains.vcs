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

- `freechains chains add ...`:         creates or clones chain locally
- `freechains chain post ...`:         posts to chain (signed with SSH)
- `freechains chain like/dislike ...`: rates post or author
- `freechains chain list dag/order`:   lists all posts (DAG or consensus order)
- `freechains chain reps ...`:         queries reputation
- `freechains chain sync send/recv`:   synchronizes with remote peer

<!--
For testing purposes, you may prepend an alternative path to store the chains:

```
freechains --root=/tmp/tests/ ...
```
-->

Follows a step-by-step execution:

- Create an SSH keypair:

```
$ ssh-keygen -t ed25519
```

The keypair in `~/.ssh/*` becomes your default identity:

```
$ ls ~/.ssh/id_ed25519*
```

- Create a chain locally:

```
$ freechains chains add '#chat' init inline --sign
#461cfb4...
```

This creates the public chain `#chat`, with you as the sole pioneer.
The output is the chain's unique identifier across all peers.

Note that the exact hash identifiers depend on local creation time and thus
will differ throughout this guide.

All application data resides in `~/.freechains/`:

```
$ ls ~/.freechains/chains/
```

- Post some content:

```
$ freechains chain '#chat' post inline $'Hello World\n' --sign
b52c62f...
$ freechains chain '#chat' post inline $'I am here\n'   --sign
d6568e4...
```

The output is each post's unique identifier.

- List all posts:

As a DAG:

```
$ freechains chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
```

In consensus order:

```
$ freechains chain '#chat' list order
b52c62f...
d6568e4...
```

- Read posts payload:

```
$ freechains chain '#chat' get payload b52c62f
Hello World
$ freechains chain '#chat' get payload d6568e4
I am here
```

- Read post metadata:

```
$ freechains chain '#chat' get metadata d6568e4
return {
    ["backs"] = {
        [1] = "b52c62f...",
    },
    ["hash"] = "d6568e4...",
    ["like"] = false,
    ["post"] = "post-1780088002-4865365518.txt",
    ["sign"] = "ssh-ed25519 AAAAC3N...",
    ["time"] = 1780088002,
    ["why"] = "(empty message)",
}
```

These are the basic steps to create keys and chains, and post and read content
locally.

### Peer-to-Peer Synchronization

- Communicate with other peers over the Internet:

As peer `A`, serve the chains with a daemon:

```
$ freechains daemon
Serving on port 8330...
```

(Switch to another terminal...)

As peer `B`, here using a separate `--root` on the same machine, clone the
chain in `A`:

```
$ freechains --root=/tmp/peer-B/ chains add '#chat' clone 127.0.0.1
#461cfb4...
```

Note that the chain id is the same in both peers.

You may now list the posts in peer `B`:

```
$ freechains --root=/tmp/peer-B/ chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
```

- Post again from `A`:

```
$ freechains chain '#chat' post inline "Sync me!\n" --sign
e1f2a3b...
```

Now, peers `A` and `B` diverge and need to synchronize.

- Synchronize with `B`:

As peer `B`, serve a daemon on another port:

```
$ freechains --root=/tmp/peer-B/ daemon --hub --port=8331
Serving on port 8331...
```

The option `--hub` allows peers to push changes to it.

(Switch to another terminal...)

As peer `A`, send the new post over `git://`:

```
$ freechains chain '#chat' sync send 127.0.0.1:8331
```

Peer `B` now holds the new post:

```
$ freechains --root=/tmp/peer-B/ chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
                    |
                 e1f2a3b
```

### Reputation & Consensus

(TODO: skip for now)
