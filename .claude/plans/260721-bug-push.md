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

## Proposed test

New step 8 in `tst/cli-send.lua`, after step 7.
`A` and `B` are bit-equal at the end of step 6.

```lua
-- 8. send to a diverged receiver (non-fast-forward)
do
    print("==> Step 8: send diverged")

    TEST "A posts (diverge)"
    local A = exec {
        cmd = EXE_A .. " --now=10000 chain '#test' post inline 'fifth from A' --sign " .. KEY1,
    }
    assert(#A == 40, "hash: " .. A)

    TEST "B posts (diverge)"
    local B = exec {
        cmd = EXE_B .. " --now=11000 chain '#test' post inline 'third from B' --sign " .. KEY1,
    }
    assert(#B == 40, "hash: " .. B)

    -- B's main is NOT a fast-forward of A's main
    TEST "B sends to A (non-fast-forward)"
    exec {
        cmd = EXE_B .. " --now=11500 chain '#test' sync send " .. REPO_A,
    }

    TEST "A holds both posts"
    local posts = dofile(REPO_A .. ".freechains/state/posts.lua")
    assert(posts[A], "A's post missing in A")
    assert(posts[B], "B's post missing in A")
end
```

Fails today with `! [rejected] ... (fetch first)`;
passes with the fix below.

## Proposed fix

| file                            | place            | change                |
|---------------------------------|------------------|-----------------------|
| `src/freechains/chain/sync.lua` | `ARGS.send` L11  | force both refspecs   |

```lua
-- before
.. URL(ARGS.remote, ARGS.alias) .. " main refs/begs/*:refs/begs/*",

-- after
.. URL(ARGS.remote, ARGS.alias) .. " +main +refs/begs/*:refs/begs/*",
```

## Pending

- [x] Reproduce via the README `### Consensus` flow
- [x] Locate root cause (`sync.lua:11`, plain `main` refspec)
- [x] Confirm no existing test covers a diverged receiver
- [ ] NEXT: add step 8 to `tst/cli-send.lua`
- [ ] Apply the `+main +refs/begs/*` fix
- [ ] Re-run the README flow; both sends print `Freechains: OK`
- [ ] Paste real hashes / fork DAG / `list order` into `README.md`
      (see `2026-06-14-readme.md`)
