# State Branch

State lives on a separate branch, always 1 commit ahead of main.
Main is local-only. State branch is transferred.

## Step 1: Genesis

```
main:    Genesis
              \
state:      [state]
               ↑
            TRANSFER
```

After genesis, create the first state commit on the state branch.

## Step 2: Mutations (post/like/time)

```
main:    Genesis → post → post → like
                                   \
state:                            [state]  ← amend on each mutation
                                     ↑
                                  TRANSFER
```

Every mutation (post, like, time-effect) amends the single state commit.
State branch always stays 1 commit ahead of main's tip.

## Step 3: Fast-forward sync

```
         TRANSFER
            ↓
         remote state
            │
            ├── post
            ├── post
            │
         [state]
```

Remote's state branch arrives with content commits + state on tip.
Strip remote state, fast-forward main, create fresh local state commit.

```
main:    Genesis → post → post → like → post → post
                                                  \
state:                                          [state] (fresh, amend from here)
                                                   ↑
                                                TRANSFER
```

## Step 4: Non-fast-forward sync (merge)

```
                     TRANSFER
                        ↓
         local state          remote state
               │                    │
               ├── post             ├── post
               ├── like             ├── post
               │                    │
            [state]              [state]
               │                    │
               └────────┬───────────┘
                        │
                      merge
                        \
                      [state]
```

Both local and remote state branches have state on tip.
States are loaded directly from tips (no walk needed).
After merge, create fresh state commit on the new main tip.

## Garbage

Amended state commits become unreachable. Never transferred (local-only
objects). Cleaned by `git gc` automatically.

## Key Properties

- **main**: content + merges only, local-only, never transferred
- **state branch**: main + 1 state commit on top, this is what gets transferred
- **state always on tip**: no walking back to find last state commit
- **checkpoint before fetch**: state commit is always available pre-transfer
