# Freechains: Permissionless Reputation Consensus over Git

[![Tests](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml/badge.svg)](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml)

Freechains is a peer-to-peer permissionless Sybil-resistant social media
protocol with integrated reputation designed on top of Git:

- Local-first publish-subscribe topic-based model
- Unstructured peer-to-peer gossip dissemination
<!--
- **Multiple flavors of public and private communication** (`1->N`, `1<-N`, `N<->N`, `1<-`)
-->
- **Per-topic reputation system for posts and authors**
- **Consensus via authoring reputation (human work)**
- **Revocation of abusive content (SPAM, hate speech)**
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
- `freechains chain list dag/order`: lists all posts (DAG or consensus order)
- `freechains chain (dis)like ...`:  rates post or author
- `freechains chain (un)revoke ...`: hides or restores post payload
- `freechains chain reps ...`:       queries reputation
- `freechains chain sync send/recv`: synchronizes with remote peer
- `freechains chain destroy ...`:    erases local history after hard fork

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

To welcome new members into the chain, the pioneer needs to redistribute a
share of its `reps`:

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

### Posts Reputation & Begging

As with authors, posts also have associated `reps` and can receive likes and
dislikes:

```
$ freechains --root=/tmp/B/ chain '#chat' like    1 post b52c62f --sign=/tmp/charlie
a9b0c1d...
$ freechains --root=/tmp/B/ chain '#chat' dislike 1 post d6568e4 --sign=/tmp/bob
b0c1d2e...
```

A like transfers `reps` from the caster to the post (half) and to its
author (half), whereas a dislike drains `reps` from them:

```
$ freechains --root=/tmp/B/ chain '#chat' reps posts
b52c62f... 1
e1f2a3b... 0
d6568e4... -1
$ freechains --root=/tmp/B/ chain '#chat' reps authors
ssh-ed25519 ...vzTc96I 20    # Alice (unaffected)
ssh-ed25519 ...je8+xIa ?     # Bob
ssh-ed25519 ...Ks9pL2v ?     # Charlie
```

As an alternative to welcome new members, Freechains supports begging posts.
Let's introduce `Dave`, who wants to join the community, but holds no `reps`:

```
$ ssh-keygen -t ed25519 -C '' -f /tmp/dave
$ freechains --root=/tmp/A/ chain '#chat' post inline $'A great post!\n' --beg --sign=/tmp/dave
c7d8e9f...
```

The `--beg` flag allows to post without `reps`, but the post is parked apart
from the chain, waiting for a like:

```
$ freechains --root=/tmp/A/ chain '#chat' list begs
c7d8e9f...
```

`Alice` likes the post and rates it, spending `4 reps`:

```
$ freechains --root=/tmp/A/ chain '#chat' like 4 post c7d8e9f --sign=/tmp/alice
d8e9f0a...
$ freechains --root=/tmp/A/ chain '#chat' list begs
# (empty)
$ freechains --root=/tmp/A/ chain '#chat' list dag
                 ...
                 560a55c
                    |
                 c7d8e9f
                    |
                 d8e9f0a
              (^560a55c)
```

The post iss now part of the chain and `Dave` becomes a proper member.
%
TODO:
Note that the like `d8e9f0a` links back to two posts: the beg `c7d8e9f` just
above it, and the previous tip of the chain, which appears as `(^560a55c)`
because it is not drawn immediately above.

In summary, the reputation system of Freechains allows to rate posts and
members, helping to distinguish quality amid excess.
In addition, the begging mechanism highlights its permissionless nature,
allowing any insider to welcome a total stranger based purely on content
quality.

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
Note that it is impossible to judge whether `Alice` was trying to rewrite
history or simply became offline for a long time.
Nevertheless, the community protects itself from late reorderings.

To resynchronize, `Alice`'s only option is to revert her local history, receive
the settled branch, repost the rejected message on top of it, and finally send
the updated history.
To revert history, Freechains provides a `destroy` command that permanently
drops a post along with everything after it:

```
# revert local history
$ freechains chain '#chat' destroy 9d0e1f2
9d0e1f2...

# receive settled branch
$ freechains chain '#chat' sync recv localhost:8331

# repost rejected message
$ freechains chain '#chat' post inline $'Alice takes over\n' --sign=/tmp/alice
3c4d5e6...

# send updated history
$ freechains chain '#chat' sync send localhost:8331
```

`Alice` is now compatible with the community again, and her message is ordered
after their settled branch.
Note that the repost is a brand new post, with a new identifier and a new
timestamp.
Note also that `Alice` requires no additional `reps`, since in reverted history
the original post never happened.

Hard forks safeguard chains against long-lived network partitions with
diverging histories.
Since it is not possible to judge the reasons behind partitions, Freechains
simply makes them incommunicable, requiring manual intervention to restore
compatibility.

### Moderation

Even considering that posts are rated through likes and dislikes, chains are
still subject to abuse, including SPAM, hate speech, and possibly illegal
content.
For such cases, Freechains provides an additional revocation mechanism that
works in conjunction with reputation.

Reputation restrains authors, but it does not remove content: a post
remains readable even after its author is drained of `reps`.
For this, Freechains provides an independent revocation axis, through the
`revoke` and `unrevoke` commands.

The two axes are coupled, but only in one direction:

| operation  | caster | post reps | revocation |
|------------|--------|-----------|------------|
| `like`     | `-n`   | `+n`      | `+n`       |
| `dislike`  | `-n`   | `-n`      | --         |
| `revoke`   | `-n`   | `-n`      | `-n`       |
| `unrevoke` | `-n`   | --        | `+n`       |

A `revoke` also counts as a `dislike`, since revoking implies disapproval,
and a `like` also counts as an `unrevoke`, since approving a post implies
that it should remain visible.
The converses do not hold: a `dislike` never hides a payload, and an
`unrevoke` never rewards a post, it only restores visibility.
All four operations spend the caster's `reps`, with the single exception
of a self-revoke, which is free (see below).

To illustrate moderation, let's have `Charlie` post some spam in peer `B`:

```
$ freechains --root=/tmp/B/ chain '#chat' post inline $'BUY NOW\n' --sign=/tmp/charlie
4a5b6c7...
```

The post is immediately readable by everyone in the chain:

```
$ freechains --root=/tmp/B/ chain '#chat' get payload 4a5b6c7
BUY NOW
```

`Bob` now revokes the spam, spending `3 reps`:

```
$ freechains --root=/tmp/B/ chain '#chat' revoke 3 4a5b6c7 --sign=/tmp/bob
8f9a0b1...
```

As shown in the table, a revoke also acts as a dislike, draining the post
and its author, but it additionally hides the payload.

The post is now revoked, which `list order` shows between `~`:

```
$ freechains --root=/tmp/B/ chain '#chat' list order
...
~4a5b6c7...~
```

And its payload is no longer available:

```
$ freechains --root=/tmp/B/ chain '#chat' get payload 4a5b6c7
ERROR : chain get : revoked post
```

Note that only the payload is hidden: the commit remains in the DAG, so
the history and the consensus order are unaffected.

Being an ordinary commit, a revoke propagates like any other post:

```
$ freechains --root=/tmp/B/ chain '#chat' sync send localhost:8331
$ freechains --root=/tmp/X/ chain '#chat' list revokes
4a5b6c7...
```

Revocation is also reversible, through the `unrevoke` command, which any
member may cast to bring a payload back.
`Alice`, who is now back in the community, disagrees with `Bob` and
spends `2 reps` to restore the post:

```
$ freechains chain '#chat' sync recv localhost:8331
$ freechains chain '#chat' unrevoke 2 4a5b6c7 --sign=/tmp/alice
2b3c4d5...
$ freechains chain '#chat' get payload 4a5b6c7
ERROR : chain get : revoked post
```

The post remains revoked, since revocation is `reps`-weighted, and not a
head count: a payload stays hidden while the revokes outweigh the
unrevokes.
`Alice` spent `2 reps` against the `3 reps` from `Bob`, and would need
`1 rep` more to make the post visible again.
The `reps revoke` command shows both channels, the author's and the
community's, in this order:

```
$ freechains chain '#chat' reps revoke 4a5b6c7
0 -1
```

The plural form lists both channels of all posts, most revoked first:

```
$ freechains chain '#chat' reps revokes
4a5b6c7... 0 -1
```

`Alice` could also have used a `like`, which lifts the revocation by the
same amount and, in addition, rewards the post and its author.
A `dislike` from `Bob`, on the other hand, would have drained `Charlie`
further, but would not have hidden the payload.

Members may also revoke their own posts, in a separate and absolute
channel.
Let's say `Bob` posts something he immediately regrets:

```
$ freechains --root=/tmp/B/ chain '#chat' post inline $'my address is ...\n' --sign=/tmp/bob
5d6e7f8...
$ freechains --root=/tmp/B/ chain '#chat' revoke 1 5d6e7f8 --sign=/tmp/bob
6e7f8a9...
```

A self-revoke is free: it spends no `reps` and works even for an author
with no reputation left.
It is also absolute: no amount of `reps` from the community can bring the
payload back.

```
$ freechains --root=/tmp/B/ chain '#chat' unrevoke 4 5d6e7f8 --sign=/tmp/charlie
7f8a9b0...
$ freechains --root=/tmp/B/ chain '#chat' get payload 5d6e7f8
ERROR : chain get : revoked post
```

This is because authors and community vote in separate channels, and a
post stays hidden while either of them is negative.
Only `Bob` can lift his own revocation, and this one does spend `reps`:

```
$ freechains --root=/tmp/B/ chain '#chat' unrevoke 1 5d6e7f8 --sign=/tmp/bob
8a9b0c1...
```

Note that moderation is always per-chain and per-peer: there is no global
authority to censor content, and each chain holds its own `reps`.
Members that disagree with a revocation are free to fork the chain and
carry on separately, since nobody is forced to relay unwanted content.

In summary, moderation in Freechains is just another use of `reps`: those
who contribute the most to a chain also hold the most weight to protect
it, while authors keep the last word over their own posts.
