# State Order: ordered post/like vector

## Context

Chain state tracks `authors.lua` and `posts.lua` but has no
record of the **order** in which posts/likes were applied.
The skel already has `state/order.lua` (empty placeholder).

This activates `state/order.lua` — a flat vector of post/like
commit hashes in consensus order — and a read-only CLI command.

## Implementation Progress

| Step | Description            | Status      |
|------|------------------------|-------------|
| 1    | G.order field + load   | [x] done |
| 2    | Track in apply         | [x] done |
| 3    | write(G) persists      | [x] done |
| 4    | CLI `order` command    | [ ] pending |
| 5    | Sync integration       | [ ] pending |
| 6    | Test                   | [x] done |

## File format (state/order.lua)

```lua
return {
    "abc123...",  -- post
    "def456...",  -- like
    "ghi789...",  -- post
}
```

Only post/like hashes. No state, merge, or genesis.

## Files to modify

| File | Place | Change |
|------|-------|--------|
| `chain/common.lua` | `write(G)` | serialize `G.order` |
| `chain/common.lua` | `apply()` | append `T.hash` on success |
| `chain/init.lua` | G load | add `order = dofile(...)` |
| `chain/init.lua` | dispatch | `ARGS.order` branch |
| `chain/like.lua` | T table | add `hash = hash` |
| `chain/sync.lua` | replay like T | add `hash = hash` |
| `chain/sync.lua` | G_com load | add order field |
| `chain/sync.lua` | G_end load | add order field |
| `freechains.lua` | argparse | add `order` command |
| `chain/order.lua` | **new** | print `G.order` |

Skel `state/order.lua` already exists — no change needed.

## Step 1–3: G.order + apply + write

**common.lua apply()** — after successful post/like,
before cap:

```lua
if T and T.hash then
    G.order[#G.order+1] = T.hash
end
```

**common.lua write(G)** — add:

```lua
f(G.order, FC .. "state/order.lua")
```

**init.lua** — G load adds:

```lua
order = dofile(FC .. "state/order.lua"),
```

**like.lua** — add `hash = hash` to T table.
**sync.lua** — add `hash = hash` to replay like T.

## Step 4: CLI command

`chain <alias> order` — one hash per line.

**freechains.lua**: add `order = {}` to cmd.chain,
define command.

**chain/order.lua** (new):

```lua
for _, hash in ipairs(G.order) do
    print(hash)
end
```

## Step 5: Sync

- **FF**: remote `order.lua` adopted (part of state tree)
- **Non-FF**: G_end.order = winner entries; loser replay
  appends via apply; write(G_end) persists merged vector

**sync.lua G_com** and **G_end** loads add `order` field.
