# Split replay() into two functions

## Scope

Pure refactor. No semantic changes. Tests pass after.

Split current `replay(G, com, fst, snd)` at
`sync.lua:49` into two functions matching the two
call sites. Per-commit logic is copy/pasted — not
extracted to a shared helper.

## Split

| Current call                     | New function                   |
|----------------------------------|--------------------------------|
| `replay(G_rem, com, nil, rem)`   | `replay_remote(G, com, rem)`   |
| `replay(G_end, com, fst, snd)`   | `replay_loser(G, com, fst, snd)` |

### replay_remote(G, com, rem)

Remove all `if fst` blocks from current `replay`:
- No detached checkout
- No `<close>` cleanup
- No trial-merge per commit

Keeps: signature verification, forgery check, trailer
parse, like metadata read, `apply` call.

### replay_loser(G, com, fst, snd)

Keep current `replay` body as-is; drop the `if fst`
guards since `fst` is always provided.
- Always detached checkout at `fst`
- Always `<close>` cleanup
- Always trial-merge per commit

## Rename

`G_end` → `G_fst` at sync.lua:218-230. `G_end` holds
the winner's state (either loaded from disk when
`fst == loc`, or `G_rem` when `fst == rem`). `G_fst`
makes this explicit and aligns with `fst/snd` used at
the consensus call.

## Files to modify

### Split refactor

| File             | Place        | Change                         |
|------------------|--------------|--------------------------------|
| `chain/sync.lua` | line 49-147  | Remove old `replay()`          |
| `chain/sync.lua` | new local    | `replay_remote(G, com, rem)`   |
| `chain/sync.lua` | new local    | `replay_loser(G, com, fst, snd)` |
| `chain/sync.lua` | line 204     | `replay(G_rem, com, nil, rem)` → `replay_remote(G_rem, com, rem)` |
| `chain/sync.lua` | line 218-230 | `G_end` → `G_fst`; `replay(...)` → `replay_loser(...)` |

### Semantic change (after split passes)

| File               | Place             | Change                  |
|--------------------|-------------------|-------------------------|
| `chain/common.lua` | `apply()` line 165-167 | Remove `if T and T.hash then G.order[...]` |
| `chain/post.lua`   | after `apply` succeeds, before state commit | `G.order[#G.order+1] = hash` |
| `chain/like.lua`   | after `apply` succeeds, before state commit | `G.order[#G.order+1] = hash` |
| `chain/sync.lua`   | `replay_remote` per-commit loop | `G.order[#G.order+1] = hash` after apply |
| `chain/sync.lua`   | `replay_loser` body | Rewrite: iterate `G_snd.order` from divergence with `G_fst.order`; apply each hash; append to `G_fst.order` |
| `chain/sync.lua`   | before replay_loser call | Load `G_snd = dofile/F` from snd state commit (local or git show) |

## Implementation Steps

| Step | Description                        | Status      |
|------|------------------------------------|-------------|
| 1    | Add replay_remote                  | [x] done    |
| 2    | Add replay_loser                   | [x] done    |
| 3    | Wire replay_remote at line 204     | [x] done    |
| 4    | Wire replay_loser at line 230      | [x] done    |
| 5    | Rename G_end → G_fst               | [x] done    |
| 6    | Remove old replay()                | [x] done    |
| 7    | Test: split refactor passes        | [x] done    |
| 8    | Extract G.order append from apply  | [x] done    |
| 9    | Append hash in post.lua            | [x] done    |
| 10   | Append hash in like.lua            | [x] done    |
| 11   | Append hash in replay + merge      | [x] done    |
| 11b  | Append HEAD/com/loc on load        | [x] done    |
| 12   | Rewrite replay_loser via G.order   | [x] done    |
| 13   | Test: semantic change passes       | [x] done    |

## Semantic change: replay_loser via G.order

### Rationale

Every post/like commit is immediately followed by a
state commit (post.lua:60-69, like.lua). HEAD is
therefore always a state commit, and
`git show snd:state/order.lua` is always the
complete consensus-ordered sequence — no linear
tail needed.

Loser's order shares a prefix with `G_com.order`
(everything before the merge-base). Commits to
replay are `G_snd.order[i..end]` where `i` is the
first index after the common prefix.

### Algorithm

```
G_snd = load state from snd (local disk if
        snd == loc, else git show snd:state/*)
-- linear search for divergence with G_fst.order
-- (both orders contain only post/like hashes)
i = find last common hash
for j = i+1, #G_snd.order do
    hash = G_snd.order[j]
    -- signature check, trailer, like metadata,
    -- trial-merge, apply (same per-commit logic)
    G_fst.order[#G_fst.order+1] = hash
end
```

### Order append extracted from apply

`apply()` at common.lua:165-167 currently appends to
G.order. This is a replay-level concern, not a
state-mutation concern. `apply(G, 'reps', ...)`
already skips it (no T.hash), so removal is safe.
Callers handle their own append:

- post.lua, like.lua: append after successful apply
- replay_remote: append in the per-commit loop
- replay_loser: append as it iterates G_snd.order
