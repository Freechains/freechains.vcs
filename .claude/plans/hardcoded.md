# Hardcoded Settings

All magic numbers currently hardcoded in the codebase.
These may become configurable per chain (via `genesis.lua`)
in the future.

## Timestamp Validation

| Setting   | Value | Unit    | Where            |
|-----------|-------|---------|------------------|
| TOLERANCE | 3600  | seconds | `src/freechains` |

- **TOLERANCE**: Maximum allowed clock drift.
  Used in monotonic check: `commit.ts >= parent.ts - 1h`.
  Will also be used in future check at fetch time:
  `commit.ts <= receiver.now + 1h`.
- Planned: configurable via `genesis.lua` field `tolerance`.

## Reputation

| Setting            | Value | Unit     | Where            | Status |
|--------------------|-------|----------|------------------|--------|
| REP_SCALE          | 1000  | factor   | `src/freechains` | impl   |
| PIONEER_REPS       | 30000 | internal | `src/freechains` | impl   |
| POST_COST          | 1000  | internal | `src/freechains` | impl   |
| MAX_REPS           | 30000 | internal | —                | planned|
| LIKE_TAX           | 10%   | ratio    | `src/freechains` | impl   |
| LIKE_SPLIT         | 50/50 | ratio    | `src/freechains` | impl   |
| DISLIKE_MIN        | 3     | count    | —                | planned|
| POST_SIZE          | 131072| bytes    | —                | planned|

- **REP_SCALE**: 1 external rep = 1000 internal.
  Conversion: `ext = sign(int) * (abs(int) + 999) // 1000`.
- **PIONEER_REPS**: 30 external (30000 internal) split
  equally among pioneers at chain creation (Rule 1.a).
- **POST_COST**: Creating a post costs 1 external rep
  (1000 internal) from the author. Temporary — refunded
  after variable discount period (Rule 2).
- **MAX_REPS**: Author reputation capped at 30 external
  (30000 internal). Incentivizes spending likes to
  decentralize (Rule 4.b).
- **LIKE_TAX**: 10% of like value is burned
  (`num * 9 // 10`).
- **LIKE_SPLIT**: For post-targeted likes, delivered value
  splits 50/50 between post author and post reputation.
- **DISLIKE_MIN**: Minimum dislikes for revocation.
  A post is REVOKED when dislikes >= 3 AND dislikes > likes
  (Rule 3.b).
- **POST_SIZE**: Maximum post payload size: 128 KB.
  Prevents DDoS via gigantic blocked posts (Rule 4.c).

## Time Windows

| Setting            | Value  | Unit    | Status  |
|--------------------|--------|---------|---------|
| DISCOUNT_MAX       | 43200  | seconds | planned |
| DISCOUNT_THRESHOLD | 0.5    | ratio   | planned |
| CONSOLIDATION      | 86400  | seconds | planned |
| EMISSION_RATE      | 1      | per day | planned |
| HARD_FORK          | 604800 | seconds | planned |

- **DISCOUNT_MAX**: 12 hours. Maximum discount period for
  new posts (Rule 2). The actual discount varies from 0 to
  DISCOUNT_MAX based on subsequent reputed activity.
  Formula: `DISCOUNT_MAX * max(0, 1 - 2*ratio)` where
  `ratio = subsequent_reps / total_reps`.
- **DISCOUNT_THRESHOLD**: 0.5 (50%). When subsequent reputed
  activity reaches this fraction of total chain reputation,
  the discount drops to zero (instant refund).
- **CONSOLIDATION**: 24 hours. A post must be at least 24h
  old before it can consolidate and grant +1 rep to its
  author (Rule 1.b).
- **EMISSION_RATE**: At most 1 consolidated post per author
  per day generates reputation. This is the only way to
  create new reps (Rule 1.b).
- **HARD_FORK**: 7 days. Branches separated by >7 days
  trigger permanent consensus divergence.

## Related Plans

- [time.md](time.md) — timestamp validation rules
- [reps.md](reps.md) — reputation system
- [consensus.md](consensus.md) — fetch validation pipeline
- [references.md](references.md) — papers, docs, guides
