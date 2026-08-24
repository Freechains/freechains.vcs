# Freechains: Permissionless Peer-to-Peer Forums

[![Tests](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml/badge.svg)](https://github.com/Freechains/freechains.vcs/actions/workflows/tests.yml)

[
    [About](#about)     |
    [Install](#install) |
    [Docs](#docs)
]

# About

A member posts a message to a chain (a forum topic) and other members in the
same chain eventually receive the message.
Members spend reputation tokens, known as `reps`, to post new messages and gain
`reps` as they consolidate.
Members can like and dislike messages from other members, which transfer `reps`
between them.

<img src="doc/freechains.png" width="250" align="right">

Main features:

- Local-first publish-subscribe topic-based model
- Unstructured peer-to-peer gossip dissemination
- **Permissionless and Sybil-resistant chains**
- **Per-chain reputation system for posts and authors**
- **Consensus via authoring reputation (human work)**
- **Revocation of abusive content (SPAM, hate speech)**
- Built on top of Git
- Free in all senses

<!--
- **Multiple flavors of public and private communication** (`1->N`, `1<-N`, `N<->N`, `1<-`)
-->

*(In bold we highlight what we believe is particular to Freechains.)*

By "Sybil-resistant", we mean that extra identities are innocuous:
    a fresh key holds zero `reps` and cannot post in a chain.
By "permissionless", we mean that no central authority controls membership:
    any member can welcome any newcomer in a chain.

## Install

Freechains is implemented in Lua (`>=5.4`) on top of Git.

Install dependencies:

```
sudo apt install git openssh-client lua5.4 luarocks
```

Install via LuaRocks:

```
sudo luarocks --lua-version=5.4 install freechains
```

Verify that `freechains` is installed:

```
freechains --version
```

## Docs

- [Command-line interface](doc/cli.md)
    - reference of all `freechains` commands
- [Guide](doc/guide.md)
    - basics, synchronization, reputation, consensus, hard forks, moderation
- [Reputation system](doc/reps.md)
    - rules and design goals

<!--
    - Basics:                     create keys and chains, post and read content
    - Synchronization:            serve and exchange chains between peers
    - Reputation:                 spend and transfer `reps` to post and welcome members
    - Consensus:                  order diverging branches by authoring reputation
    - Hard Forks:                 protect settled branches from late reorderings
    - Moderation:                 revoke and restore abusive payloads
-->

<!--
- Main concepts:
    - [Chain](docs/chains.md):   list of blocks (aka topic or feed]
    - [Block](docs/blocks.md):   unit of information (aka post or message)
    - [Consensus](docs/cons.md): consensus order of chains
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
