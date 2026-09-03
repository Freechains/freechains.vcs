# Freechains: Command-Line Interface

[
    [Daemon](#daemon) |
    [Chains](#chains) |
    [Chain](#chain)
]

```
freechains v0.21

Usage:
    freechains daemon start [--port=<port>] [--hub] [-- <git-opts>...]
    freechains daemon stop [--port=<port>]

    freechains chains dir
    freechains chains add <alias> init [--dictator=<pub>]... [--pioneer=<pub>]...
    freechains chains add <alias> clone <url>
    freechains chains rem <alias>

    # per-chain

    # actions
    freechains chain <alias> post (file <path> | inline <text>) [--beg]
    freechains chain <alias> like <n> (action <id> | member <pub>) [--file=<path>]
    freechains chain <alias> dislike <n> (action <id> | member <pub>)
    freechains chain <alias> revoke <n> <id>
    freechains chain <alias> unrevoke <n> <id> [--file=<path>]

    # queries
    freechains chain <alias> list (tips | begs | revokes | dag | order)
    freechains chain <alias> get (metadata | payload) <id>
    freechains chain <alias> reps (actions | members | revokes)
    freechains chain <alias> reps (action <id> | member <pub> | revoke <id>)

    # synchronize
    freechains chain <alias> sync (recv | send) <remote>

    # bookkeeping
    freechains chain <alias> abandon <id> [--keep]
    freechains chain <alias> sweep

Options:
    -h --help                      displays this help
    -v --version                   displays software version
    --root=<dir>    [all]          data directory [default: ~/.freechains/]
    --now=<secs>    [all]          overrides current time [default: local clock]
    --sign=<pvt>    [actions]      signs with key [default: ~/.ssh/id_ed25519]
    --why=<text>    [votes]        explains vote reason

Chain URLs:
    - Prefix (directory):
    <host>                         port defaults to 8330
    <host>:<port>                  explicit port
    <path>                         local path (starts with / ~ .)
    <scheme>://<...>               full url

    - Suffix (chain):
    (none)                         default local <alias> (unless `/` in prefix)
    /<alias>                       remote alias
    /<cid>                         remote chain id

Keys:
    ssh-<...>       [pub]          a key string
    <path>          [pub|pvt]      a key file, public or private (+ `.pub`)
    <none>          [pub|pvt]      `$HOME/.ssh/id_ed25519`

More Information:

    https://github.com/Freechains/freechains.vcs/

Please report bugs:

    https://github.com/Freechains/freechains.vcs/issues
```

# Daemon

## daemon start

Starts daemon to serve local chains to remote peers.

```
freechains daemon start [--port=<port>] [--hub] [-- <git-opts>...]
```

- `--port=<port>`:  port to listen [default: 8330]
- `--hub`:          accepts `sync send` from peers
- `<git-opts>...`:  extra options forwarded to `git daemon`

- Examples:

```
freechains daemon start
freechains --root=/tmp/X/ daemon start --hub --port=8331 &
```

## daemon stop

Stops running daemon.

```
freechains daemon stop [--port=<port>]
```

- `--port=<port>`:  port to stop [default: 8330]

- Examples:

```
freechains daemon stop --port=8331
```

# Chains

Operations over the set of local chains.

## chains dir

Lists all chains.

```
freechains chains dir
```

## chains add

Creates a chain, either from scratch (`init`) or from a remote peer (`clone`).

```
freechains chains add <alias> init [--dictator=<pub>]... [--pioneer=<pub>]...
freechains chains add <alias> clone <url>
```

- `<alias>`:                chain name (requires prefix `/`)
- `init`:                   creates new chain
    - `--dictator=<pub>`:   repeat for each dictator key
    - `--pioneer=<pub>`:    repeat for each pioneer key
- `clone <url>`:            fetches existing chain from peer

If no dictators or pioneers are given, the chain is *open* and anyone may
post.

As result, displays the chain id, unique across all peers.

- Examples:

```
freechains chains add /chat init --dictator
freechains chains add /chat init --pioneer=alice.pub --pioneer=bob.pub
freechains chains --root=/tmp/X/ add /chat clone ~/.freechains/chains/chat
freechains chains add /chat clone localhost:8331/talks
```

## chains rem

Drops a chain removing all of its data.

```
freechains chains rem <alias>
```

- Examples:

```
freechains chains rem /chat
```

# Chain

Operations inside a single chain:

- All take the chain `<alias>` as first argument.
- Action ids may be abbreviated to first characters.

## chain post

Posts a new action in the chain.

```
freechains chain <alias> post (file <path> | inline <text>) [--sign=<pvt>] [--beg]
```

- `file <path>`:    posts contents of given file
- `inline <text>`:  posts given text
- `--sign=<pvt>`:   private key file of member (defaults to `$HOME/.ssh/id_ed25519`)
- `--beg`:          posts without spending reps
    - post needs a like to become part of the chain

Either `--sign` or `--beg` is required (except on open chains).

- Examples:

```
freechains chain /chat post file ./pic.jpg --sign=/tmp/alice
freechains chain /chat post inline $'A great post!\n' --beg
freechains chain /open post inline $'no key at all\n'
```

## chain like / dislike

Likes or dislikes an action or member in the chain.

```
freechains chain <alias> like <n> (action <id> | member <pub>) [--why=<text>] [--file=<path>]
freechains chain <alias> dislike <n> (action <id> | member <pub>) [--why=<text>]
```

- `<n>`:                amount of reps to spend (min: 500)
- target:
    - `action <id>`:    rates action
    - `member <pub>`:   rates member
- `--why=<text>`:       justify the action
- `--file=<path>`:      original payload (required for revoked actions)

- Examples:

```
freechains chain /chat like 1000 action b52c62f --sign=/tmp/charlie
freechains chain /chat like 10000 member /tmp/bob.pub --sign=/tmp/alice
freechains chain /chat dislike 1000 action d6568e4 --sign=/tmp/bob --why='SPAM'
```

## chain revoke / unrevoke

Removes or restores the payload of an action.

```
freechains chain <alias> revoke <n> <id> [--why=<text>]
freechains chain <alias> unrevoke <n> <id> [--why=<text>] [--file=<path>]
```

- `<n>`:            amount of reps to spend
- `<id>`:           action to remove or restore payload
- `--why=<text>`:   justify the action
- `--file=<path>`:  original payload (required for revoked actions)

A revoked payload becomes immediately unavailable to `get`.

- Examples:

```
freechains chain /chat revoke 1000 4a5b6c7 --sign=/tmp/alice
freechains chain /chat unrevoke 1000 4a5b6c7 --sign=/tmp/alice --file=/tmp/f.txt
```

## chain list

Lists chain actions.

```
freechains chain <alias> list (tips | begs | revokes | dag | order)
```

- `tips`:       tips with no children
- `begs`:       pending begs only
- `revokes`:    revoked actions only
- `dag`:        DAG drawn as ASCII
- `order`:      consensus order

In `order` and `dag`, actions with revoked payloads appear as `~<id>~`.

- Examples:

```
freechains chain /chat list dag
freechains chain /chat list order
```

## chain get

Queries action with given id.

```
freechains chain <alias> get (metadata | payload) <id>
```

- `metadata`:   dump metadata as a Lua table
- `payload`:    dump actual content bytes
    - fails if action is revoked
- `<id>`:       action id or `genesis` for chain info

Metadata for a post:

```
return {
    action = "post",
    time   = 1780088002,        -- local creation time
    blob   = "90c7c77a...",     -- payload hash
    sign   = "ssh-ed25519 ...", -- member public key (optional: anonymous)
    backs  = { "b52c62f...", }, -- back-link actions, sorted
}
```

Metadata for a vote:

```
return {
    action = "like",            -- like | revoke
    time   = 1780088002,        -- local creation time
    n      = 1000,              -- amount (negative: dislike | revoke)
    cid    = "4b2080cf...",     -- target action (either this...)
    member = "ssh-ed25519 ...", -- target member (...or this)
    blob   = "9ae2f1b3...",     -- --why payload hash (optional)
    sign   = "ssh-ed25519 ...", -- voter public key
    backs  = { "b52c62f...", }, -- back-link actions, sorted
}
```

Metadata for `genesis`:

```
return {
    version   = "0.21.0",
    nonce     = 3004508805,
    dictators = { "ssh-ed25519 ...", },
    pioneers  = { "ssh-ed25519 ...", },
    open      = false,
}
```

- Examples:

```
freechains chain /chat get payload b52c62f
Hello World!
```

```
$ freechains chain /chat get metadata d6568e4
return {
    ["action"] = "post",
    ["backs"] = {
        [1] = "b52c62f...",
    },
    ["blob"] = "90c7c77...",
    ["sign"] = "ssh-ed25519 ...",
    ["time"] = 1780088002,
}
```

## chain reps

Queries reputation of given action or member.

```
freechains chain <alias> reps actions
freechains chain <alias> reps members
freechains chain <alias> reps revokes
freechains chain <alias> reps action  <id>
freechains chain <alias> reps member  <pub>
freechains chain <alias> reps revoke  <id>
```

- `actions`:        all actions, most reputable first
- `members`:        all members, most reputable first
- `revokes`:        all actions, most revoked first
- `action <id>`:    reps of single action
- `member <pub>`:   reps of single member (`anonymous` for unsigned posts)
- `revoke <id>`:    revokes of single action, as `<member> <others>`

- Examples:

```
freechains chain /chat reps member /tmp/alice.pub
freechains chain /chat reps actions
```

## chain sync

Synchronizes a chain with given peer.

```
freechains chain <alias> sync (recv | send) <remote>
```

- `send`:       sends   missing actions to   remote peer
- `recv`:       receive missing actions from remote peer
    - the remote daemon must run with `--hub`
- `<remote>`:   same url forms of `Chain URLs`

Received actions are validated and replayed.

- Examples:

```
freechains chain /chat sync recv localhost
freechains chain /chat sync send localhost:8331
```

## chain abandon

Permanently drops local action and everything after it.

```
freechains chain <alias> abandon <id> [--keep]
```

- `<id>`:   first action to drop
- `--keep`: `<id>` is instead last action to keep

- Examples:

```
freechains chain /chat abandon 9d0e1f2
freechains chain /chat abandon --keep 560a55c
```

## chain sweep

Erases revoked payloads and compacts the chain.

```
freechains chain <alias> sweep
```
