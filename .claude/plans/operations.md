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
See [2026-05-operation-modes-4way.md](2026-05-operation-modes-4way.md)
for schema, enforcement, and test matrix.

## Status

- [ ] Define CLI syntax for `post` with add/rem
- [ ] Define CLI syntax for mode at chain creation
- [ ] Implement mode enforcement in `post`
- [ ] Tests for each mode restriction
