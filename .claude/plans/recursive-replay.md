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

| File             | Place        | Change                         |
|------------------|--------------|--------------------------------|
| `chain/sync.lua` | line 49-147  | Remove old `replay()`          |
| `chain/sync.lua` | new local    | `replay_remote(G, com, rem)`   |
| `chain/sync.lua` | new local    | `replay_loser(G, com, fst, snd)` |
| `chain/sync.lua` | line 204     | `replay(G_rem, com, nil, rem)` → `replay_remote(G_rem, com, rem)` |
| `chain/sync.lua` | line 218-230 | `G_end` → `G_fst`; `replay(...)` → `replay_loser(...)` |

## Implementation Steps

| Step | Description                    | Status      |
|------|--------------------------------|-------------|
| 1    | Add replay_remote              | [x] done    |
| 2    | Add replay_loser               | [x] done    |
| 3    | Wire replay_remote at line 204 | [x] done    |
| 4    | Wire replay_loser at line 230  | [x] done    |
| 5    | Rename G_end → G_fst           | [x] done    |
| 6    | Remove old replay()            | [x] done    |
| 7    | Test: make test T=cli-sync     | [ ] pending |

## Follow-up (separate plan)

Semantic changes deferred:
- Enhanced `graph()` with parents/nparents/time
- `walk()` for independent consensus in replay_remote
- G.order-based fast path for replay_loser
- Rename file / move to a new plan when started
