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
Mode is set at chain creation time.

| Mode      | add (new) | add (overwrite) | rem | Use case              |
|-----------|-----------|-----------------|-----|-----------------------|
| `create`  | yes       | no              | no  | Immutable publishing  |
| `append`  | yes       | yes             | no  | Logs, feeds, wikis    |
| `mutable` | yes       | yes             | yes | General purpose, full |

- `create`: only new files, no overwrites, no removals.
- `append`: new files and overwrites, but no removals.
- `mutable`: full access — add, overwrite, and remove.

## Status

- [ ] Define CLI syntax for `post` with add/rem
- [ ] Define CLI syntax for mode at chain creation
- [ ] Implement mode enforcement in `post`
- [ ] Tests for each mode restriction
