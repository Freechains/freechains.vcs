# Freechains: Command-Line Interface

```
freechains v0.20.0

Usage:
    freechains daemon [--port=<port>] [--hub] [<git-daemon-opt>...]

    freechains chains add <alias> init [--pioneer=<key>]...
    freechains chains add <alias> clone <url>
    freechains chains rem <alias>
    freechains chains dir

    # per-chain

    # queries
    freechains chain <alias> list (order | dag | begs | revokes)
    freechains chain <alias> get (metadata | payload) <id>
    freechains chain <alias> reps (action | actions | author | authors)
    freechains chain <alias> reps (revoke | revokes) [<id>]

    # actions
    freechains chain <alias> post (file <path> | inline <text>) [--beg]
    freechains chain <alias> like <n> (action | author) <id> [--file=<path>]
    freechains chain <alias> dislike <n> (action | author) <id>
    freechains chain <alias> revoke <n> <id>
    freechains chain <alias> unrevoke <n> <id> [--file=<path>]

    # synchronize
    freechains chain <alias> sync (recv | send) <remote>

    # bookkeeping
    freechains chain <alias> abandon <id> [--keep]
    freechains chain <alias> sweep

Options:
    -h --help                      displays this help
    -v --version                   displays software version
    --root=<dir>    [all]          data directory [default: ~/.freechains/]
    --now=<secs>    [all]          overrides current time [default: clock]
    --sign=<key>    [actions]      signs with given key [default: ~/.ssh/id_ed25519]
    --why=<text>    [votes]        explains reason for the vote

More Information:

    https://www.freechains.org/

    Please report bugs at <https://github.com/Freechains/freechains.vcs/>.
```

# daemon

Starts daemon to serve local chains.

```
freechains daemon [--port=<port>] [--hub] [<git-opts>...]
```

- `--port=<port>`: port to listen [default: 8330]
- `--hub`: accept `sync send` from peers
- `<git-opts>...`: extra options forwarded to `git daemon`

- Examples:

```
freechains daemon
freechains --root=/tmp/X/ daemon --hub --port=8331
```

# chains

Operations over the set of local chains.

## chains add

Creates a chain locally, from scratch or from a remote peer.

```
freechains chains add <alias> init [--pioneer=<key>]...
freechains chains add <alias> clone <url>
```

- `<alias>`: local name of the chain, must start with `#`
- `init`: creates a brand new chain
    - `--pioneer=<key>`: repeat once per pioneer
        - a key STRING, starting with `ssh-`
        - or a key FILE, private or public
        - with no value: `$HOME/.ssh/id_ed25519`
    - with no `--pioneer`, nobody holds reps
- `clone <url>`: fetches an existing chain from a peer

The genesis file is always generated, never supplied:

- `version`: the running version
- `pioneers`: the resolved keys, duplicates dropped

These are the only two fields any code reads back.

The output is the chain id, unique across all peers.
Two `init` calls with identical parameters still yield
different chains.

The genesis is a Lua chunk returning a table:

```lua
return {
    version  = {0, 20, 0},
    pioneers = { "ssh-ed25519 ..." },    -- share the initial reps
}
```

The pioneers share `reps.max`, so too many of them is refused.

The `<url>` of `clone` accepts:

- `<host>`: port defaults to `8330`
- `<host>:<port>`
- a local path (starting with `/`, `~` or `.`)
- a full `<scheme>://` url

The alias is appended to the url unless it already names a chain
with `#`.

- Examples:

```
freechains chains add '#chat' init --pioneer=/tmp/alice
freechains chains add '#chat' init --pioneer=/tmp/alice.pub --pioneer="$(cat /tmp/bob.pub)"
freechains chains add '#chat' init
freechains chains add '#chat' clone localhost
freechains --root=/tmp/B/ chains add '#chat' clone localhost:8331
```

## chains rem

Leaves a chain removing all of its data.

```
freechains chains rem <alias>
```

- Examples:

```
freechains chains rem '#chat'
```

## chains dir

Lists all local chains.

```
freechains chains dir
```

# chain

Operations inside a single chain.
All take the chain `<alias>` (or its `#<id>`) as first argument.

Action ids may be abbreviated, as printed by `list dag`.

## chain list

Lists the actions of the chain.

```
freechains chain <alias> list (order | dag | begs | revokes)
```

- `order`: consensus order, one id per line
    - revoked payloads appear wrapped as `~<id>~`
- `dag`: the actions DAG, drawn as ASCII
- `begs`: pending begs, still parked outside the chain
- `revokes`: revoked actions only, in consensus order

- Examples:

```
freechains chain '#chat' list dag
freechains chain '#chat' list order
```

## chain get

Gets the action with the given id.

```
freechains chain <alias> get (metadata | payload) <id>
```

- `metadata`: the action file, serialized as a Lua table
    - fields: `action`, `backs`, `blob`, `sign`, `time`
- `payload`: the actual content bytes
    - fails with `revoked payload` if the action is revoked

Payloads live outside the history, so their bytes can be erased
without affecting it.

- Examples:

```
freechains chain '#chat' get payload b52c62f
freechains chain '#chat' get metadata b52c62f
```

## chain post

Posts a new action in the chain.

```
freechains chain <alias> post file <path>   --sign=<key>
freechains chain <alias> post inline <text> --sign=<key>
```

- `file <path>`: posts the contents of the given file
- `inline <text>`: posts the given text
- `--sign=<key>`: ssh private key of the author
    - defaults to `$HOME/.ssh/id_ed25519` when given no value
- `--beg`: posts without spending reps
    - the post is parked apart from the chain, awaiting a like
    - requires no `--sign`

A post spends reps, refunded within at most 12 hours.
Either `--sign` or `--beg` is required.

- Examples:

```
freechains chain '#chat' post inline $'Hello World\n' --sign=/tmp/alice
freechains chain '#chat' post file ./pic.jpg --sign=/tmp/alice
freechains chain '#chat' post inline $'A great post!\n' --beg
```

## chain like / dislike

Likes or dislikes an action or an author in the chain.

```
freechains chain <alias> (like | dislike) <n> action <id> --sign=<key>
freechains chain <alias> (like | dislike) <n> author <pub> --sign=<key>
```

- `<n>`: amount of reps to spend, a positive integer
- `action <id>`: rates a post or a vote
    - a positive `like` on a beg admits it into the chain
- `author <pub>`: rates an author by public key
    - welcomes a newcomer holding no reps
- `--why=<text>`: reason for the vote
- `--file=<path>`: supplies the payload bytes when liking a beg
  whose content is not held locally
    - refused unless it hashes to the expected blob

Likes are taxed and split between the action and its author.
Dislikes drain reps from both.

- Examples:

```
freechains chain '#chat' like 10000 author "$(cat /tmp/bob.pub)" --sign=/tmp/alice
freechains chain '#chat' like 1000 action b52c62f --sign=/tmp/charlie
freechains chain '#chat' dislike 1000 action d6568e4 --sign=/tmp/bob --why='SPAM'
```

## chain revoke / unrevoke

Removes or restores the payload of an action.

```
freechains chain <alias> (revoke | unrevoke) <n> <id> --sign=<key>
```

- `<n>`: amount of reps to spend, a positive integer
- `<id>`: action whose payload to remove or restore
- `--why=<text>`: reason for the vote
- `--file=<path>`: supplies the payload bytes on `unrevoke`,
  when they were already erased by `sweep`

Revocation is a vote on its own axis, independent of likes.
Authors may always revoke their own posts for free.
A revoked payload becomes immediately unavailable to `get`.

- Examples:

```
freechains chain '#chat' revoke 1000 4a5b6c7 --sign=/tmp/alice
freechains chain '#chat' unrevoke 1000 4a5b6c7 --sign=/tmp/alice
```

## chain reps

Gets the reputation of an action (id) or an author (public key).

```
freechains chain <alias> reps action  <id>
freechains chain <alias> reps actions
freechains chain <alias> reps author  <pub>
freechains chain <alias> reps authors
freechains chain <alias> reps revoke  <id>
freechains chain <alias> reps revokes
```

- `action <id>`: reps of a single action
- `actions`: all actions, most reputable first
- `author <pub>`: reps of a single author
- `authors`: all authors, most reputable first
- `revoke <id>`: revoke votes of an action, as `<author> <others>`
- `revokes`: revoke votes of all actions, most revoked first

- Examples:

```
freechains chain '#chat' reps author "$(cat /tmp/alice.pub)"
freechains chain '#chat' reps actions
```

## chain abandon

Permanently drops a local action and everything after it.

```
freechains chain <alias> abandon <id> [--keep]
```

- `<id>`: first action to DROP
- `--keep`: `<id>` is instead the last action to KEEP

Local only: no signing, no network, no reps.
Only a linear suffix may go, never crossing a sync merge.
This is the escape hatch to recover from a hard fork.

- Examples:

```
freechains chain '#chat' abandon 9d0e1f2
freechains chain '#chat' abandon --keep 560a55c
```

## chain sweep

Erases the bytes that removal already unreferenced.

```
freechains chain <alias> sweep
```

Reclaims revoked and abandoned payloads, and packs the state
snapshots.
Local only: no signing, no network, no reps.
Never run it against a concurrent writer.

## chain sync

Synchronizes a chain with a given peer.

```
freechains chain <alias> sync (recv | send) <remote>
```

- `send`: sends   missing actions to   remote peer
- `recv`: receive missing actions from remote peer
    - the remote daemon must run with `--hub`
- `<remote>`: same url forms accepted by `chains add clone`

Received actions are validated and replayed.
If the merge would reorder our settled actions, it is refused
with `hard fork`.

- Examples:

```
freechains chain '#chat' sync recv localhost
freechains chain '#chat' sync send localhost:8331
```
