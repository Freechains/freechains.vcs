# Plan: like record per-target field shape

## Goal

Rename fields in the `like` record so the shape is
self-discriminating: the *presence* of `post` vs `author` is the
target type. The `target` field is removed.

| Old shape                                            | New shape           |
|------------------------------------------------------|---------------------|
| `{ target="post",   id="<40-hex>",  number=±N }`     | `{ post="<40-hex>",  n=±N }` |
| `{ target="author", id="ssh-ed25519 <b64>", number=±N }` | `{ author="ssh-ed25519 <b64>", n=±N }` |

Rationale: a single ambiguous `id` field (40-hex hash *or*
ssh-ed25519 pubkey) hides a type distinction the consumer must
re-derive. Naming the target field after the target type itself
removes the discriminator-plus-payload redundancy and makes the
shape self-describing. Aligns `n` with Kotlin `Like.n`.

## Status

All steps complete; awaiting test run.

| Step | Item                                                        | State    |
|------|-------------------------------------------------------------|----------|
| 1    | `chain/like.lua` — `payload` template (file format)         | done     |
| 2    | `chain/like.lua` — in-memory `T` build                      | done     |
| 3    | `chain/common.lua` — `apply(... 'like' ...)` reads           | done     |
| 4    | `chain/sync.lua` — like validation (if any)                 | done     |
| 5    | `chain/get.lua` — block branch like extraction              | done     |
| 6    | `tst/cli-like.lua` — assertions                             | done     |
| 7    | `tst/err-like.lua` — assertions                             | done     |

## Like-file format change

### Before (current)

```lua
return {
    target = "post" | "author",
    id     = "<40-hex>" | "ssh-ed25519 <b64>",
    number = ±N * C.reps.unit,
}
```

### After (this plan)

```lua
-- post target
return {
    post = "<40-hex>",
    n    = ±N * C.reps.unit,
}

-- author target
return {
    author = "ssh-ed25519 <b64>",
    n      = ±N * C.reps.unit,
}
```

Validation rule: exactly one of `post` or `author` must be set.

## Affected reads — `chain/common.lua` `apply()`

Current code in `apply(... 'like' ...)` references:

- `T.target`
- `T.id`
- `T.num`

Becomes presence-based dispatch:

- `if T.post then  ... end` (post-target branch)
- `if T.author then ... end` (author-target branch)
- `T.n`

Internal `T` table (built by `chain/like.lua`) uses the same
new fields.

## `get block` integration

`chain/get.lua` block branch loads the like file and emits the
table verbatim — no rename mapping needed once the storage
already uses the new shape:

```lua
if kind == 'like' then
    local L = assert(assert(load(f))())
    like = L      -- direct passthrough: { post=..., n=... } or { author=..., n=... }
end
```

(The current code does `like = { n=L.number, target=L.target, id=L.id }` —
that mapping disappears.)

## Migration

| Concern                              | Decision                                       |
|--------------------------------------|------------------------------------------------|
| Existing on-disk `.freechains/likes/like-*.lua` | break compat — no migration shim         |
| Wire format (`sync recv` from old peer) | not addressed — tests rebuild from scratch |
| Version bump (`VERSION` constant)    | no                                             |

Existing test chains under `/tmp/freechains/` are wiped by
`make tests` between runs, so no on-disk data persists.

## Tests

Existing `cli-like.lua`/`err-like.lua` cases continue covering
the like flow. Assertions that read like-file fields update from
`target`/`id`/`number` → `post`/`author`/`n`.

The "bad-target-type" forge case (`target="xxx"`) is rewritten
as a like with no `post` and no `author` key — semantically the
same: no recognized target. Error text unchanged.

No new tests required for the rename itself (the existing tests
exercise the full read/write round-trip). The `block` branch in
`chain/get.lua` test already asserts `T.like.post/author/n`
(after the related test update — in plan
`2026-04-chain-get.md`).

## Out of scope

- Block of unsigned-post test (covered in `2026-04-chain-get.md`).
- The rest of the `chain get` feature (in `2026-04-chain-get.md`).
- Any change to dislike (just inverts `n`'s sign).
- Wire-format / sync compatibility with prior versions.

## Errors

No new error cases. Existing `chain like : invalid <…>` errors
keep their text.
