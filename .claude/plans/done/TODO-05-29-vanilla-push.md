# Plan: vanilla push — transparent begs from a stock git client

## Context

A peer with **only `git`** (no freechains installed) pushes to a
freechains server.
The server must absorb the pushed commits as **begs** (powerless,
zero-reputation contributions awaiting a local like) instead of
rejecting the push.

This was Steps 8-9 of `2026-04-begs.md`, now extracted here.

## Current behavior (to change)

`src/freechains/hooks/pre-receive` rejects any push that lacks the
`freechains=true` option:

```lua
if not freechains then
    die "missing freechains push option"
end
```

So a stock `git push` cannot contribute at all today.

## Asymmetry vs. official begs

| | official | vanilla (this plan) |
|----------------|--------------------------------|----------------------------|
| sender | freechains node | any git client |
| push options | `freechains=true` + `url=` | none |
| validation | hook calls `recv <url>` | hook walks `old..new` local|
| merge policy | consensus / divergence | **FF-only** |
| result | posts/likes with reputation | every commit -> beg |

The vanilla sender cannot be called back (no `recv`), so the server
does the only safe thing: park every pushed commit as a beg.

## Design

### pre-receive route

Replace the `die "missing freechains push option"` branch.
When the push has **no** `freechains=true`:

1. Assert single ref `refs/heads/main`.
2. Assert FF: `new` is a descendant of `old` (`merge-base
   --is-ancestor old new`).
   Non-FF -> reject (no merge protocol without signed state).
3. Invoke the new subcommand with the pushed range:

```
freechains --root=<r> chain <n> sync _beg <old> <new>
```

The objects are already local (the push delivered them), so `_beg`
does **no** fetch.

### `sync _beg <old> <new>` subcommand

Walk `old..new` oldest-first; for each commit register a beg:

```lua
-- for hash in git rev-list --reverse old..new:
apply(G, 'post', time, { hash=hash, sign=key, beg=true })
git update-ref refs/begs/beg-<hash> <hash>
```

Then write + commit the beg-only state update.

### Signature handling (design requirement, was Step 9)

Begs grant no power, so a bad signature is harmless -- never reject.

| pushed commit | `key` | beg recorded as |
|----------------------|--------|------------------------|
| valid signature | pubkey | beg, author = signer |
| unsigned | nil | beg, no author |
| forged signature | nil | beg, no author |

Contrast official `commit()` (`sync.lua` forged check) which throws
`invalid post : invalid signature`.
The vanilla path must downgrade forged -> anonymous, not abort.

## Files (proposed)

| File | Place | Change |
|------------------------------------|---------------|--------------------------------------------|
| `src/freechains/hooks/pre-receive` | option parse | no `freechains=true` -> FF check + call `sync _beg <old> <new>` |
| `src/freechains/hooks/pre-receive` | ref loop | pass `old`/`new` through to the subcommand |
| `src/freechains.lua` | parser | add private `_beg` leaf under `chain <n> sync` |
| `src/freechains/chain/sync.lua` | new `ARGS._beg` branch | walk range, register begs, lenient signatures, write state |
| `src/freechains/chain/common.lua` | helper | beg-registration helper if shared with recv |

## Steps

1. `pre-receive`: route no-option push to FF check + `_beg`.
2. `sync _beg`: walk `old..new`, register each commit as a beg.
3. Lenient signatures: forged/unsigned -> anonymous beg (no reject).
4. Beg-only state commit on the receiver (see open question on key).

## Open questions

- Who signs the receiver-side state commit?
  No owner key is present on a vanilla push.
  Options: receiver-owned key, or an unsigned state commit for
  beg-only updates.
- `refs/begs/<id>` naming: hash (content-addressed) vs. seq/time
  (ordering-friendly).
- Can official + vanilla pushes coexist on one chain, or must each
  peer relationship pick a mode?
- Lockless safety: a concurrent vanilla push creating beg refs while
  the stale-beg cleanup (`sync.lua` `::RECV::` block) deletes merged
  beg refs.

## Source

Extracted from `2026-04-begs.md` Steps 8-9.
