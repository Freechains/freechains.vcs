# Plan: `sync send` hides receiver-side rejections

## Symptom

`sync send` exits 0 and prints nothing, while the receiver silently
voided the whole pushed branch:

```
$ freechains --root=/tmp/B/ chain '#chat' sync send localhost:8331
$ (nothing)
```

The same push, run raw, shows what really happened:

```
remote: ERROR : invalid like : too old
remote: Freechains: OK
```

The sender believes it synchronized; the hub kept none of its posts.

## Root cause

`lua/freechains/hooks/pre-receive:46-52` runs the receiver's
`sync recv`, then prints `Freechains: OK` and exits 1 whenever
`os.execute` returned success.

But `recv` exits 0 even when it voids the sender's branch: the loser
replay treats validation failures as non-fatal, writing the reason to
stderr and continuing (`src/freechains/chain/sync.lua:404-419`).
So `OK` means "the recv ran", not "your posts were accepted".

`src/freechains/chain/sync.lua:13-18` then matches `Freechains: OK` in
the push stderr and discards the whole message, including the
`ERROR : ...` lines that came with it.

The `voided : <hash>` listing does not help either: it only prints when
the remote branch wins (`sync.lua:423`), and here the receiver's own
branch won.

## Impact

Silent data loss from the sender's point of view.
A peer can push for hours and keep nothing on the hub, with no signal.
This is how the README `### Consensus` run failed unnoticed: the
receiver rejected a like as `too old` and `send` reported success.

## Options

1. Print the remote's stderr on success, stripping only the
   `Freechains: OK` marker.
   Smallest change, keeps the current control flow.
2. Make the hook distinguish outcomes, e.g. `Freechains: OK` versus
   `Freechains: VOID`, and have `send` exit non-zero on the latter.
   Clearer contract, but the receiver deciding to void the loser is a
   normal consensus result, not an error.
3. Have `send` report what the receiver kept, by echoing the receiver's
   `voided :` lines.
   Requires `recv` to emit them in the local-wins case too.

Option 1 is the minimum to stop the silence; option 3 is the useful
end state.

## Files

| file                            | place            | change                 |
|---------------------------------|------------------|------------------------|
| `src/freechains/chain/sync.lua` | `ARGS.send` L13  | stop discarding stderr |
| `lua/freechains/hooks/pre-receive` | L46-52        | (option 2 only)        |

## Test

`tst/consensus.lua` Test 1 already drives a merge through `send`.
A companion case needs the loser branch to be rejected on the receiver,
then asserts that `send` surfaces the reason.

## Pending

- [x] Diagnose (hook prints `OK` regardless; `send` discards stderr)
- [ ] NEXT: pick option 1, 2 or 3
- [ ] Implement + test
- [ ] Related: `C.time.diff` is 1h, so any branch that diverged more
      than an hour ago is voided on merge
      (`src/freechains/chain/common.lua:70`, `constants.lua:9`)
