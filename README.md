# Freechains: Permissionless Reputation Consensus over Git

[![Tests](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml/badge.svg)](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml)

Freechains is a peer-to-peer permissionless social media protocol with
integrated reputation designed on top of Git:

- Local-first publish-subscribe topic-based model
- Unstructured peer-to-peer gossip dissemination
<!--
- **Multiple flavors of public and private communication** (`1->N`, `1<-N`, `N<->N`, `1<-`)
-->
- **Per-topic reputation system for healthiness**
- **Consensus via authoring reputation (human work)**
- Free in all senses

*(In bold we highlight what we believe is particular to Freechains.)*

A user posts a message to a chain (a topic) and other users in the same chain
eventually receive the message.
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

- `freechains chains add ...`:       creates or clones chain locally
- `freechains chain post ...`:       posts to chain (signed with SSH)
- `freechains chain (dis)like ...`:  rates post or author
- `freechains chain list dag/order`: lists all posts (DAG or consensus order)
- `freechains chain reps ...`:       queries reputation
- `freechains chain sync send/recv`: synchronizes with remote peer

<!--
For testing purposes, you may prepend an alternative path to store the chains:

```
freechains --root=/tmp/tests/ ...
```
-->

### Basics

To operate on the chains, `Alice` first needs to create an SSH keypair:

```
$ ssh-keygen -t ed25519 -C '' -f /tmp/alice
```

`Alice` can now create a chain locally:

```
$ freechains chains add '#chat' init inline --sign=/tmp/alice
#461cfb4...
```

This creates the public chain `#chat`, with `Alice` as the sole pioneer.
The output is the chain's unique identifier across all peers.

Note that the exact hash identifiers depend on local creation time and thus
will differ throughout this guide.

All application data resides in `~/.freechains/`:

```
$ ls ~/.freechains/chains/
```

With the chain set, we can now post some content:

```
$ freechains chain '#chat' post inline $'Hello World\n' --sign=/tmp/alice
b52c62f...
$ freechains chain '#chat' post inline $'I am here\n'   --sign=/tmp/alice
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
    ["sign"] = "ssh-ed25519 ...vzTc96I",
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
$ freechains --root=/tmp/B/ chains add '#chat' clone localhost
#461cfb4...
```
Note that the chain id is the same in both peers (`#461cfb4...`).

We may now list the posts in peer `B`:

```
$ freechains --root=/tmp/B/ chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
```

To illustrate how peers synchronize over time, let's post again in peer `A`:

```
$ freechains chain '#chat' post inline $'Sync me\n' --sign=/tmp/alice
e1f2a3b...
```

Peer `B` is now outdated and needs to synchronize:

```
$ freechains --root=/tmp/B/ chain '#chat' sync recv localhost
```

Peer `B` now holds the new post from `A`:

```
$ freechains --root=/tmp/B/ chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
                    |
                 e1f2a3b
```

Note that synchronization is always explicitly peer-to-peer, through `recv` (or
`send`).

### Reputation

Let's introduce new user `Bob` who will act through peer `B`:

```
$ ssh-keygen -t ed25519 -C '' -f /tmp/bob
```

Since `Bob` has no previous reputation, he cannot yet post on the chain:

```
$ freechains --root=/tmp/B/ chain '#chat' post inline $'Possibly malicious\n' --sign=/tmp/bob
ERROR : chain post : insufficient reputation
```

Let's query the public keys from both users:

```
$ cat /tmp/alice.pub
ssh-ed25519 ...vzTc96I 
$ cat /tmp/bob.pub
ssh-ed25519 ...je8+xIa 
```

Now, we use their public keys to query their reputations:

```
$ freechains chain '#chat' reps author "$(cat /tmp/alice.pub)"
29
$ freechains chain '#chat' reps author "$(cat /tmp/bob.pub)"
0
```

As the chain pioneer, `Alice` still has `29 reps` to use, whereas `Bob` has no
reputation and cannot post on the chain.

To welcome new users into the chain, the pioneer needs to redistribute a share
of its `reps`:

```
$ freechains chain '#chat' like 10 author "$(cat /tmp/bob.pub)" --sign=/tmp/alice
560a55c...
```

`Alice` just transferred `10 reps` to `Bob`:

```
$ freechains --root=/tmp/B/ chain '#chat' sync recv localhost
$ freechains --root=/tmp/B/ chain '#chat' reps author "$(cat /tmp/alice.pub)"
20
$ freechains --root=/tmp/B/ chain '#chat' reps author "$(cat /tmp/bob.pub)"
9
```

You might have expected `19` and `10`, not `20` and `9` as `reps`.
This is due to internal rules that tax transfers and recover `reps` over time,
which are out of the scope of this guide.

Let's now introduce new user `Charlie`, who is welcomed by `Bob` in peer `B`:

```
$ ssh-keygen -t ed25519 -C '' -f /tmp/charlie
$ freechains --root=/tmp/B/ chain '#chat' like 5 author "$(cat /tmp/charlie.pub)" --sign=/tmp/bob
$ freechains --root=/tmp/B/ chain '#chat' reps author "$(cat /tmp/alice.pub)"
20
$ freechains --root=/tmp/B/ chain '#chat' reps author "$(cat /tmp/bob.pub)"
4
$ freechains --root=/tmp/B/ chain '#chat' reps author "$(cat /tmp/charlie.pub)"
5
```

After a few interactions, we already have `Alice`, `Bob`, and `Charlie` with
non-zero reputation in the chain.

Freechains is permissionless not in the sense that outsiders can post freely,
but rather that any insider can welcome any outsider to participate.

### Consensus

<!--
As peer `B`, serve a daemon on another port:

```
# (switch to new terminal)
$ freechains --root=/tmp/B/ daemon --hub --port=8331
Serving on port 8331...
```

The option `--hub` allows peers to push changes to it.

As peer `A`, send the new post to peer `B` on port `8331`:

```
$ freechains chain '#chat' sync send localhost:8331
```
-->
