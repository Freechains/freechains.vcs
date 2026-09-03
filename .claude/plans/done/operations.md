# Operations

## File Operations

Only two primitive operations:

| Operation | Description                        |
|-----------|------------------------------------|
| `add`     | Add or overwrite a file in a chain |
| `rem`     | Remove a file from a chain         |

- `mv` is not primitive — it is `rem` + `add`.
- Directory operations are sugar for multiple single-file ops.

## Chain Modes

Each chain has a mode that restricts which operations are
allowed.
Mode is set at chain creation time and is **immutable**.
Modes form a strict hierarchy: `create` < `append` < `remove` <
`edit`.

| Mode     | new file | extend | delete path | rewrite content | Use case              |
|----------|----------|--------|-------------|-----------------|-----------------------|
| `create` | yes      | no     | no          | no              | Immutable publishing  |
| `append` | yes      | yes    | no          | no              | Logs, feeds, wikis    |
| `remove` | yes      | yes    | yes         | no              | Append-only + GC      |
| `edit`   | yes      | yes    | yes         | yes             | General purpose, full |

- `create`: only new files, no extends, no deletions, no rewrites.
- `append`: new files and content extension (byte-prefix), no deletions.
- `remove`: append + path deletion, no rewrites.
- `edit`: full access — add, extend, delete, rewrite.

`extend` means the new blob's bytes start with the parent
blob's bytes (byte-prefix check).

Rationale for ordering: `edit` can simulate removal by rewriting
a blob to empty content, so `edit` is strictly more permissive
than `remove`.

## Schema

The chain's mode is stored as a `mode` field in
`.freechains/config.lua` (immutable like the rest of the config):

```lua
return {
    version = {0, 11, 0},
    type    = '#',
    mode    = 'edit',                -- 'create'|'append'|'remove'|'edit'
    -- shared = "x25519:def...",     -- '$' only
    -- key    = "ed25519:abc...",    -- '@'/'@!' only
    time = { ... },
    reps = { ... },
    like = { ... },
}
```

Mandatory field.
Validated on creation and on clone.
Omission or unknown value is a hard error.

## Decision: lax `edit` (resolved 2026-05-02)

`edit` allows rewriting content **and** real `git rm`.
Rationale: `edit` is the most permissive mode by definition;
forcing users to rewrite-to-empty for deletion is friction
without security benefit.

| Option   | Path deletion in `edit`        | Chosen |
|----------|--------------------------------|--------|
| strict   | only via rewrite-to-empty-blob |        |
| lax      | real `git rm` allowed          | yes    |

## Enforcement

Per commit, diff the new tree against parent tree.
Classify every changed path:

| Diff result                               | Operation   | Required mode |
|-------------------------------------------|-------------|---------------|
| path absent in parent, present in child   | new         | create+       |
| present in both, child blob = parent ++ X | extend      | append+       |
| present in both, child blob diverges      | rewrite     | edit          |
| present in both, child blob is empty      | empty-erase | remove+       |
| present in parent, absent in child        | rm          | remove+       |

`append` check: child blob's bytes start with parent blob's
bytes (byte-prefix).
Cheap; works for any file type.
Identical blobs count as a valid no-op extend.

`config.lua` and `authors.lua` are immutable regardless of mode.

## Implementation plan

| File                                      | Change                                                      |
|-------------------------------------------|-------------------------------------------------------------|
| `src/freechains/chains.lua`               | Validate `mode` in config on create/clone                   |
| `src/freechains/chain/post.lua`           | Enforce mode against parent tree diff                       |
| `src/freechains/chain/sync.lua`           | Enforce mode in `commit()` and FF path during recv          |
| `tst/cli-chains.lua`                      | Tests for `mode` field validation                           |
| `tst/cli-post.lua`                        | 4 modes x 5 ops enforcement tests                           |

## Test matrix

| #  | Mode    | Op           | Expected                       |
|----|---------|--------------|--------------------------------|
| 1  | create  | new          | ok                             |
| 2  | create  | extend       | reject                         |
| 3  | create  | rewrite      | reject                         |
| 4  | create  | empty-erase  | reject                         |
| 5  | create  | rm           | reject                         |
| 6  | append  | new          | ok                             |
| 7  | append  | extend       | ok                             |
| 8  | append  | rewrite      | reject                         |
| 9  | append  | empty-erase  | reject                         |
| 10 | append  | rm           | reject                         |
| 11 | remove  | new          | ok                             |
| 12 | remove  | extend       | ok                             |
| 13 | remove  | rewrite      | reject                         |
| 14 | remove  | empty-erase  | ok                             |
| 15 | remove  | rm           | ok                             |
| 16 | edit    | new          | ok                             |
| 17 | edit    | extend       | ok                             |
| 18 | edit    | rewrite      | ok                             |
| 19 | edit    | empty-erase  | ok                             |
| 20 | edit    | rm           | ok                             |

## Open questions

1. Is `authors.lua` immutable like `config.lua`? (likely yes)
2. Should "no change" (identical blob) be allowed in `create`
   mode? (yes, as a no-op)

## Status

- [x] Resolve strict-vs-lax `edit` decision (lax)
- [x] Define 4-way mode table
- [x] Define schema (`mode` field in `config.lua`)
- [ ] Define CLI syntax for `post` with add/rem
- [ ] Define CLI syntax for mode at chain creation
- [ ] Implement `mode` validation in `chains.lua`
- [ ] Implement per-commit enforcement in `post.lua` and `sync.lua`
- [ ] Add config validation tests
- [ ] Add 4 x 5 enforcement tests

For the immediate `create`-only milestone, see
[2026-05-create-only.md](2026-05-create-only.md).
