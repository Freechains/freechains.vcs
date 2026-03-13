# Hardcoded Settings

All magic numbers currently hardcoded in the codebase.
These may become configurable per chain (via `genesis.lua`)
in the future.

## Timestamp Validation

| Setting   | Value | Unit    | Where              |
|-----------|-------|---------|--------------------|
| TOLERANCE | 3600  | seconds | `src/freechains`   |

- **TOLERANCE**: Maximum allowed clock drift.
  Used in monotonic check: `commit.ts >= parent.ts - 1h`.
  Will also be used in future check at fetch time:
  `commit.ts <= receiver.now + 1h`.
- Planned: configurable via `genesis.lua` field `tolerance`.

## Reputation

| Setting    | Value  | Unit     | Where            |
|------------|--------|----------|------------------|
| REP_SCALE  | 1000   | factor   | `src/freechains` |
| POST_COST  | 1000   | internal | `src/freechains` |
| LIKE_TAX   | 10%    | ratio    | `src/freechains` |
| LIKE_SPLIT | 50/50  | ratio    | `src/freechains` |

- **REP_SCALE**: 1 external rep = 1000 internal.
  Conversion: `ext = sign(int) * (abs(int) + 999) // 1000`.
- **POST_COST**: Creating a post costs 1 external rep
  (1000 internal) from the author.
- **LIKE_TAX**: 10% of like value is burned
  (`num * 9 // 10`).
- **LIKE_SPLIT**: For post-targeted likes, delivered value
  splits 50/50 between post author and post reputation.

## Time Windows

| Setting    | Value  | Unit    | Status  |
|------------|--------|---------|---------|
| MATURATION | 43200  | seconds | planned |
| HARD_FORK  | 604800 | seconds | planned |

- **MATURATION**: 12 hours. Posts must sit in the DAG for
  12h before reputation effects are settled.
- **HARD_FORK**: 7 days. Branches separated by >7 days
  trigger permanent consensus divergence.

## Related Plans

- [time.md](time.md) — timestamp validation rules
- [reps.md](reps.md) — reputation system
- [consensus.md](consensus.md) — fetch validation pipeline
