# Plan: Bug — `sync send` fails against a diverged receiver

## Symptom

Running the `README.md` `### Consensus` flow, the second `sync send`
to the hub `X` fails:

```
$ freechains --root=/tmp/B/ chain '#chat' sync send localhost:8331
To git://localhost:8331/#chat
 ! [rejected]        main -> main (fetch first)
error: failed to push some refs to 'git://localhost:8331/#chat'
```

`X` ends up with a linear DAG holding only `Alice`'s branch;
`Bob`'s post never reaches the hub, so consensus never runs.

## Root cause

`src/freechains/chain/sync.lua:10-11` pushes the plain refspec `main`.

`Alice` pushes first, the hub applies her branch through its own
`sync recv`, and the hub's `main` moves ahead.
`Bob`'s `main` is then a non-fast-forward, so **git aborts on the
client side** and the hub's `pre-receive` hook never runs.
Since the hook is the only thing that triggers the hub's `sync recv`,
the divergence is never resolved.

Divergence is exactly the case the hub exists to resolve, so a
non-fast-forward push is the normal case, not an error.

## Why forcing is safe

`lua/freechains/hooks/pre-receive:52` always ends in `os.exit(1)`.
The push therefore **never** updates any ref on the receiver.
It is only a trigger: the receiver pulls the objects itself by running
`sync recv` back against the sender's `url`.
Forcing the refspec changes what the client is willing to *send*, not
what the receiver is willing to *store*.

## Test gap

No existing test sends into a receiver that has diverged.

| test                | divergence? | merge trigger      |
|---------------------|-------------|--------------------|
| `tst/consensus.lua` | yes (1-4)   | `recv` / `clone`   |
| `tst/cli-send.lua`  | yes (5)     | `recv`             |
| `tst/cli-send.lua`  | no (3,4)    | `send` (ff only)   |
| `tst/cli-send.lua`  | no (2)      | `send` (hook fail) |
| `tst/sync.lua`      | no          | `send` (ff only)   |

The cell `send` x diverged is empty across the whole suite.

`tst/consensus.lua` covers the algorithm well (local wins, remote wins,
cascade, nested cascade), but always drives it through `recv` or
`clone`.
That is why the algorithm is solid while the push transport is broken:
the failure happens in the send path, before any consensus code runs.

## Test

`tst/consensus.lua` Test 1 now drives the merge through `send`
instead of `recv`.
No duplicated setup, and the transport becomes part of the consensus
story.

`B sends to A` is equivalent to `A recvs from B`, since the hook makes
`A` run the recv, so all assertions hold unchanged.
`B`'s `main` is not a fast-forward of `A`'s, which is the failing case.

```lua
TEST "B sends to A, non-ff (A wins by prefix reps)"
exec {
    cmd = EXE_B .. " --now=3000 chain '#cons-a' sync send " .. ROOT_A .. "/chains/#cons-a/",
}
```

Test 2 stays on `recv`: it asserts on stdout
(`ERROR : content conflict\nvoided : ...`), which under `send` goes to
the hook's stderr and would need reworking.

Confirmed failing before the fix.

## Fix

| file                            | place            | change                |
|---------------------------------|------------------|-----------------------|
| `src/freechains/chain/sync.lua` | `ARGS.send` L11  | force both refspecs   |

```lua
-- before
.. URL(ARGS.remote, ARGS.alias) .. " main refs/begs/*:refs/begs/*",

-- after
.. URL(ARGS.remote, ARGS.alias) .. " +main +refs/begs/*:refs/begs/*",
```

## Side finding: hook drops `--now`

`lua/freechains/hooks/pre-receive:41-44` invokes the receiver's
`sync recv` without `--now`.
Consensus stays deterministic, since `recv` derives time from commit
dates (`NOW(oct)`, `src/freechains/chain/common.lua:5`) and not from
`CMD.now`.
But the receiver's final state commit uses `CMD.git`
(`src/freechains/chain/sync.lua:454`), which is empty without `--now`,
so that commit gets a wall-clock date.
Not covered by any test: the `no wall-clock timestamps` assertion in
`tst/cli-send.lua` step 5 runs on a direct `recv`.

## Pending

- [x] Reproduce via the README `### Consensus` flow
- [x] Locate root cause (`sync.lua:11`, plain `main` refspec)
- [x] Confirm no existing test covers a diverged receiver
- [x] Convert `tst/consensus.lua` Test 1 to `send`; confirmed failing
- [x] Apply the `+main +refs/begs/*` fix
- [ ] NEXT: re-run `tst/consensus.lua`, then the full suite
- [ ] Decide on the `--now` side finding (forward it from the hook?)
- [ ] Re-run the README flow; both sends print `Freechains: OK`
- [ ] Paste real hashes / fork DAG / `list order` into `README.md`
      (see `2026-06-14-readme.md`)
