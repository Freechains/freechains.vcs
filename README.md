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

### Basics

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

With the chain set, we can now post some content:

```
$ freechains chain '#chat' post inline $'Hello World\n' --sign
b52c62f...
$ freechains chain '#chat' post inline $'I am here\n'   --sign
d6568e4...
```

The output is each post's unique identifier.

We can list all posts in the chain:

- As a DAG:

```
$ freechains chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
```

- In consensus order:

```
$ freechains chain '#chat' list order
b52c62f...
d6568e4...
```

We can also query each post individually:

- Post payload:

```
$ freechains chain '#chat' get payload b52c62f
Hello World
$ freechains chain '#chat' get payload d6568e4
I am here
```

- Post metadata:

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

### Synchronization

We can share the chains with other peers over the Internet.

We first need to start a daemon to serve synchronization requests:

```
# (switch to new terminal)
$ freechains daemon
Serving on port 8330...
```

As peer `A`, we now listen for requests on default port `8330`.

To simulate a remote peer `B`, we will use a separate `--root` as prefix to the
commands.

As peer `B`, we clone the chain `#chat` served by peer `A`:

```
$ freechains --root=/tmp/peer-B/ chains add '#chat' clone localhost
#461cfb4...
```
Note that the chain id is the same in both peers (`#461cfb4...`).

You may now list the posts in peer `B`:

```
$ freechains --root=/tmp/peer-B/ chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
```

To illustrate how peers synchonize over time, let's post again in peer `A`:

```
$ freechains chain '#chat' post inline $'Sync me\n' --sign
e1f2a3b...
```

Peer `B` is now outdated and needs to synchronize:

```
$ freechains --root=/tmp/peer-B/ chain '#chat' sync recv localhost
```

Peer `B` now holds the new post from `A`:

```
$ freechains --root=/tmp/peer-B/ chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
                    |
                 e1f2a3b
```

<!--
As peer `B`, serve a daemon on another port:

```
# (switch to new terminal)
$ freechains --root=/tmp/peer-B/ daemon --hub --port=8331
Serving on port 8331...
```

The option `--hub` allows peers to push changes to it.

As peer `A`, send the new post to peer `B` on port `8331`:

```
$ freechains chain '#chat' sync send localhost:8331
```
-->

Note that synchronization is always explicitly peer-to-peer, through `recv` (or
`send`).

### Reputation

Let's introduce a new user `Bob` that will act through peer `B`:

```
$ ssh-keygen -t ed25519 -f /tmp/peer-B/bob
```

Since `Bob` has no previous reputation, he cannot yet post on the chain:

```
$ freechains chain '#chat' post inline $'Possibly malicious\n' --sign=/tmp/peer-B/bob
ERROR : chain post : insufficient reputation
```

Let's query the public keys from both users:

```
$ cat ~/.ssh/id_ed25519.pub ;   # <-- you
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMIF9tHWFQPIoV7vwhk1/Cdh20XxDFme804wcvzTc96I xxx@xxx.com
$ cat /tmp/peer-B/bob.pub       # <-- Bob
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE2Cb41DBUuNgju+Y1pfhgN18N3yE/IRDRtFbje8+xIa yyy@yyy.com
```

Now, let's query their reputations:

```
$ freechains chain '#chat' reps author 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMIF9tHWFQPIoV7vwhk1/Cdh20XxDFme804wcvzTc96I'
29
$ freechains chain '#chat' reps author 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE2Cb41DBUuNgju+Y1pfhgN18N3yE/IRDRtFbje8+xIa'
0
```

As the chain pioneer, you still have `29 reps` to use, whereas `Bob` has no
reputation and cannot post on the chain.

To welcome new users into the chain, the pioneer needs to redistribute a share
of its `reps`:

```
$ freechains chain '#chat' like 10 author 'ssh-ed25519 ...je8+xIa' --sign
560a55ce9a983ff505429da5719c0fe46a304414
```

We just transferred `10` of your `reps` to `Bob`:

```
$ freechains chain '#chat' reps author 'ssh-ed25519 ...vzTc96I'
20
$ freechains chain '#chat' reps author 'ssh-ed25519 ...je8+xIa'
10
```

(For now, let's ignore why the pioneer went from `29` to `20`, not to `19`).


The permissionless nature of Freechains comes not from the fact that XXX, but
that YYY.

### Consensus
