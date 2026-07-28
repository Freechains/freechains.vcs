# Freechains: Permissionless Reputation Consensus over Git

[![Tests](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml/badge.svg)](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml)

Freechains is a peer-to-peer permissionless Sybil-resistant social media
protocol with integrated reputation designed on top of Git:

- Local-first publish-subscribe topic-based model
- Unstructured peer-to-peer gossip dissemination
<!--
- **Multiple flavors of public and private communication** (`1->N`, `1<-N`, `N<->N`, `1<-`)
-->
- **Per-topic reputation system for healthiness**
- **Consensus via authoring reputation (human work)**
- Free in all senses

*(In bold we highlight what we believe is particular to Freechains.)*

A member posts a message to a chain (a topic) and other members in the same
chain eventually receive the message.
Members spend reputation tokens, known as `reps`, to post new messages and gain
`reps` as they consolidate.
Members can like and dislike messages from other members, which transfer `reps`
between them.

By "Sybil-resistant", we mean that extra identities grant no power:
    a fresh key holds zero `reps` and cannot act in a chain.
By "permissionless", we mean that no central authority gatekeeps membership:
    any member can welcome any newcomer in a chain.

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

A chain is backed by a Git repository, with an independent commit history from
other chains.

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

A post is backed by a Git commit in the chain repository.

We can list all posts in the chain...

- ...as a DAG:

```
$ freechains chain '#chat' list dag
                 b52c62f
                    |
                 d6568e4
```

- ...in consensus order:

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

These are the basic steps in Freechains to create keys and chains, and to post
and read content locally.

### Synchronization

We can share the chains with other peers over the Internet.

We first need to start a daemon to serve synchronization requests:

```
# (switch to new terminal)
$ freechains daemon
Serving on port 8330...
```

As peer `A`, we now listen for requests on default port `8330`.

To simulate a remote peer `B`, we will use a separate `--root` as the prefix of
all commands.

Now, as peer `B`, we clone the chain `#chat` served by peer `A` at `localhost`
(default port `8330`):

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

Note that synchronization in Freechains is always explicitly peer-to-peer,
through `recv` (or `send`) commands.

Synchronization is backed by Git commands like `daemon`, `push` and `fetch`.

### Reputation

Members need reputation tokens, known as `reps`, to post on the chains.
Without this protection, chains would be open to spam and abuse from malicious
users.

Let's introduce new user `Bob` who will act through peer `B`:

```
$ ssh-keygen -t ed25519 -C '' -f /tmp/bob
```

Since `Bob` has no previous reputation, he cannot yet post on the chain:

```
$ freechains --root=/tmp/B/ chain '#chat' post inline $'Possibly malicious\n' --sign=/tmp/bob
ERROR : chain post : insufficient reputation
```

Reputation is the key aspect that makes Freechains Sybil-resistant.

Note that Git itself provides no reputation mechanism.
Therefore, Freechains relies on custom Git hooks to validate commits according
to its reputation rules.

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

To welcome new members into the chain, the pioneer needs to redistribute a share
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

Let's now introduce new member `Charlie`, who is welcomed by `Bob` in peer `B`:

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
non-zero reputations in the chain.

In summary, the reputation system makes Freechains
    Sybil-resistant (write operations require and spend `reps`) and
    permissionless (any insider can welcome any outsider transferring `reps`).

### Consensus

Freechains provides a consensus mechanism that enforces the same order for all
posts in all peers, regardless of the receiving order in each peer.
Since Git itself provides no consensus mechanism for diverging branches,
Freechains applies a custom hook to order first branches whose authors hold
more `reps`.

To illustrate how consensus resolves, let's introduce a neutral peer `X` that
never posts, acting only as a *hub* to which other peers push their posts:

```
$ freechains --root=/tmp/X/ chains add '#chat' clone localhost
#461cfb4...
# (switch to new terminal)
$ freechains --root=/tmp/X/ daemon --hub --port=8331
Serving on port 8331...
```

Now `Alice` and `Charlie` post at the same time, from peers `A` and `B`, without
synchronizing:

```
$ freechains chain '#chat' post inline $'Alice was here\n' --sign=/tmp/alice
a1b2c3d...
$ freechains --root=/tmp/B/ chain '#chat' post inline $'Charlie was here\n' --sign=/tmp/charlie
f4e5d6c...
```

Each peer now holds a diverging history with its own exclusive post:

```
$ freechains chain '#chat' list dag
                 ...
                 560a55c
                    |
                 a1b2c3d
$ freechains --root=/tmp/B/ chain '#chat' list dag
                 ...
                 560a55c
                    |
                 9a8b7c6
                    |
                 f4e5d6c
```

Note that peer `B` also holds `9a8b7c6`, which is Bob's like on Charlie, still
unknown to peer `A`.

Then, both peers `A` and `B` send their posts to the neutral hub `X`:

```
$ freechains chain '#chat' sync send localhost:8331
$ freechains --root=/tmp/B/ chain '#chat' sync send localhost:8331
```

`X` now holds both branches as a fork in its DAG:

```
$ freechains --root=/tmp/X/ chain '#chat' list dag
                 ...
                 560a55c
                  /   \
             a1b2c3d  9a8b7c6
                         |
                      f4e5d6c
```

We can also list the posts in consensus order to see which branch wins:

```
$ freechains --root=/tmp/X/ chain '#chat' list order
...
a1b2c3d...
9a8b7c6...
f4e5d6c...
```

Since `Alice` holds more `reps` than `Bob` and `Charlie` together, the branch
with her post is ordered first.
Note that the same order holds for all peers after they synchronize.

Consensus via authoring reputation is the key aspect of Freechains, making all
peers reach the same state without any central authority.

### Hard Forks

As a measure against malicious members with strong past reputation, Freechains
protects settled local branches from unexpected consensus reorderings.
A settled branch is a branch with at least *100 posts* or *7 days* between
oldest and newest posts.
Posts older than this window are frozen and cannot be reordered.
So, if a `sync` operation would reorder frozen posts in a settled branch, then
the merge is simply refused and the peers are no longer compatible.
In contrast, peers that remain active and synchronize over time evolve together
with a stable order.

To illustrate hard forks, let's make peers `X` and `B` with `Bob` and `Charlie`
to synchronize continuously over time, while peer `A` with `Alice` goes offline
just after the consensus above.

Over the next days, `Bob` and `Charlie` keep posting and syncing to the hub:

```
$ freechains --root=/tmp/B/ chain '#chat' post inline $'day 1\n' --sign=/tmp/bob
1a2b3c4...
$ freechains --root=/tmp/B/ chain '#chat' sync send localhost:8331
... # (days go by)
$ freechains --root=/tmp/B/ chain '#chat' post inline $'day 7\n' --sign=/tmp/charlie
7d8e9f0...
$ freechains --root=/tmp/B/ chain '#chat' sync send localhost:8331
```

Their posts on `X` now span over more than seven days, making hub's branch
settled and refusing reorderings.

Then, `Alice` comes back and posts locally in peer `A`, on the same branch she
left behind:

```
$ freechains chain '#chat' post inline $'Alice takes over\n' --sign=/tmp/alice
9d0e1f2...
```

When she tries to send it, the hub refuses to merge:

```
$ freechains chain '#chat' sync send localhost:8331
remote: ERROR : chain sync : hard fork
```

Regardless of her strong past reputation, `Alice` cannot affect an active
community.
To resynchronize, her only option is to revert her local history, receive the
settled branch, repost the rejected message on top of it, and finally send the
updated history.
Note that it is impossible to judge whether `Alice` was trying to rewrite
history or simply became offline for a long time.
Nevertheless, the community protects itself from late reorderings.

Hardforks safeguards chains from long-lived network partitions with diverging
histories.
Since it is not possible to judge the reasons behind partitions, Freechains
simply makes them incommunicable, requiring manual intervention to restore
compatibility.

### Moderation

- TODO
- Members dislike posts and authors, transferring `reps` away
- A single community `revoke` hides a payload, and `unrevoke` restores it
- An author self-revoke is free and absolute (right to be forgotten)
- Moderation is per-chain and per-peer: no global authority censors
- Anyone may fork a chain: nobody is forced to relay unwanted content
