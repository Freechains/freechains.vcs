# Rename post field `state` -> `maturity`

Clarity rename. The post-record field `state` only ever holds
time-**maturation** values, so `maturity` names it honestly and
removes the overload noted in `260721-revoke.md`.

## Scope

Rename ONLY the post-record field `G.posts[h].state`.

Values it holds: `'00-12'`, `'12-24'`, `nil`, `'beg'`
(see `common.lua:163`).

## DO NOT touch (same word, different meaning)

- `.freechains/state/` directory (path strings).
- `Freechains: state` commit trailer / `kind == 'state'`.
- `state/posts.lua`, `state/authors.lua`, `state/order.lua`.

These are the *serialized state store* and the *commit type*,
unrelated to the post maturation field.

## Sites (post-record field only)

| file | line | access |
|-------------------|------|--------------------------|
| `common.lua`      | 86   | `entry.state == "00-12"` |
| `common.lua`      | 111  | `entry.state = "12-24"`  |
| `common.lua`      | 120  | `entry.state == "12-24"` |
| `common.lua`      | 126  | `entry.state = nil`      |
| `common.lua`      | 163  | `state = (T.beg and ...)`|
| `common.lua`      | 215  | `G.posts[T.post].state = "00-12"` |

Verify (grep) there are no `.state` reads in `sync.lua`,
`get.lua`, `list.lua`, `reps.lua` before finalizing.

## Back-compat

`maturity`/`state` is a serialized key in
`.freechains/state/posts.lua`, which is committed and synced.
Renaming changes the on-disk format:

- old chains have `state = ...`; new code reads `maturity`.
- posts.lua is rewritten by `write(G)` on every post/like/sync,
  but existing committed history still carries the old key.

Decision: acceptable break for pre-release chains (fresh repos
in tests). No migration shim unless real chains exist.

## Open questions

- Is any external consumer reading `posts.lua`'s `state` key
  directly (outside the Lua code)? If so, migration needed.

## Progress

- [x] grep-confirmed sites: 8 source + 3 tests (plan's 6 was
      stale — also `sync.lua:193` `.maturity=="beg"` and the
      test reads in `cli-send`/`cli-recv`/`cli-begs`)
- [x] renamed `state` -> `maturity` at all sites (+ re-aligned
      the post-record literal)
- [x] confirmed `state/` dir, `Freechains: state` trailer,
      `state/*.lua` writes all untouched
- [x] all tests pass (2026-07-22)

## Actual sites renamed

| file | change |
|-----------------|-------------------------------------------|
| `common.lua`    | `entry.maturity` ×5, record literal, `G.posts[T.post].maturity` |
| `sync.lua:193`  | `.maturity=="beg"` (beg detection) |
| `cli-send.lua`, `cli-recv.lua` | post-record `.maturity` compare |
| `cli-begs.lua`  | `posts[BEG].maturity ~= "beg"` |

## Cross-references

- `260721-revoke.md` — the clash note that motivated this.
