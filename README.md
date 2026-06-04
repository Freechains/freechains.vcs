# Freechains: Peer-to-peer Content Dissemination over Git

[![Tests](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml/badge.svg)](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml)

Freechains is a permissionless social media protocol with integrated
reputation designed on top of Git:

- Local-first publish-subscribe topic-based model
- Unstructured peer-to-peer gossip dissemination
<!--
- **Multiple flavors of public and private communication** (`1->N`, `1<-N`, `N<->N`, `1<-`)
-->
- **Per-topic reputation system for healthiness**
- **Consensus via authoring reputation (human work)**
- Free in all senses

*(In bold we highlight what we believe is particular to Freechains.)*

A user posts a message to a chain (a topic) and other users subscribed to the
same chain eventually receive the message.
Users spend reputation tokens, known as `reps`, to post new messages and gain
`reps` as they consolidate.
Users can like and dislike messages from other users, which transfer `reps`
between them.

<!--
- Main concepts:
    - [Chain](docs/chains.md):   list of blocks (aka topic or feed]
    - [Block](docs/blocks.md):   unit of information (aka post or message)
    - [Reps](docs/reps.md):      reputation system of chains
    - [Consensus](docs/cons.md): consensus order of chains
- [Commands](docs/cmds.md): list of all protocol commands
- [Other systems](docs/others.md): comparison with other systems
- [Google group](https://groups.google.com/forum/#!forum/freechains):
    discussion group about Freechains
- [Resources](docs/join.md):
    publicly available chains, identities and peers
- [Source code](https://github.com/Freechains/freechains.kt/)
- [Android dashboard](https://github.com/Freechains/android-dashboard/):
    manage/navigate your peers/chains
- Introductory videos:
    [1/3](https://www.youtube.com/watch?v=7_jM0lgWL2c) |
    [2/3](https://www.youtube.com/watch?v=bL0yyeVz_xk) |
    [3/3](https://www.youtube.com/watch?v=APlHK6YmmFw)
-->

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

## Guide

Freechains' API is straightforward:

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

These are the basic steps to create keys and chains, and to post and read
content locally.

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
$ freechains --root=/tmp/peer-B/ chains add '#chat' clone localhost
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
$ freechains chain '#chat' post inline $'Sync me\n' --sign
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

As peer `A`, send the new post to peer `B` on port `8331`:

```
$ freechains chain '#chat' sync send localhost:8331
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
