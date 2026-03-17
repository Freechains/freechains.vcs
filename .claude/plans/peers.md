# Peers: Discovery, Reputation, and Network

## Overview

How the peer-to-peer overlay network forms, grows, and
self-organizes over time.
Peers are not discovered all at once — the network starts
small and expands through trust and activity.

## Peer Storage

Each host stores its known peers in a single file at the
host level (outside chains):

```
<root>/peers.lua
```

The file is **shared** (replicated between owner nodes)
and **mutable** (updated as peers join, leave, or change
reputation).

```lua
return {
    ["192.168.1.10:8330"] = {
        reps   = 5,
        chains = { "a1b2c3...", "d4e5f6..." },
    },
    ["freechains.org:8330"] = {
        reps   = true,
        chains = { "a1b2c3..." },
    },
    ["10.0.0.99:8330"] = {
        reps   = false,
        chains = {},
    },
    ["203.0.113.42:8330"] = {
        reps   = 12,
        chains = { "a1b2c3...", "f7g8h9..." },
    },
}
```

### Fields

| Field    | Type              | Description                            |
|----------|-------------------|----------------------------------------|
| `reps`   | number/bool       | Peer reputation (see below)            |
| `chains` | list of hashes    | Genesis hashes the peer declares it has |

The `chains` list is **self-declared** — the peer tells you
which chains it has during sync.
It is not verified until an actual fetch/push is attempted.

## Peer Reputation

Each peer has a `reps` field that controls sync behavior.
Reputation is **global across chains** — a peer's
behavior on any chain affects its standing everywhere.

| Value           | Meaning                                |
|-----------------|----------------------------------------|
| `reps = N`      | Numeric reputation, earned over time   |
| `reps = true`   | Trust blindly — accept everything      |
| `reps = false`  | Reject blindly — refuse all sync       |

### Reputation Signals

Numeric reputation increases or decreases based on
peer behavior:

| Signal                  | Effect   |
|-------------------------|----------|
| New valid messages      | +reps    |
| Sync failures           | −reps    |
| Rejected branches       | −reps    |
| Timeout / unreachable   | −reps    |

Peers with low or zero reputation are deprioritized
or dropped from the active peer list.

### Trust Overrides

- `reps = true`: for owner peers, F2F contacts, or
  seed nodes — skip per-message validation
- `reps = false`: for banned or known-bad peers —
  refuse connection entirely

These are manual overrides set by the node operator.
Numeric reputation is computed automatically.

## Bootstrap

New nodes start with a minimal set of known addresses:

- **Pre-loaded**: hardcoded seed peers (e.g.,
  `freechains.org`)
- **F2F (friend-to-friend)**: manually added addresses
  from trusted contacts
- **Centralized relay**: `freechains.org` acts as an
  always-on seed node for initial connectivity

A fresh node has at least one path into the network.

## Organic Growth

Peers learn about new peers from two sources:

1. **Incoming requests**: a peer that connects to you
   becomes a candidate peer
2. **Known peers**: peers share their own peer lists
   during sync (gossip-style discovery)

Discovery is passive — no DHT, no broadcast.
The overlay grows transitively through pairwise sync.

## Rate Limiting

Incoming peer discovery must be rate-limited to prevent
spam and resource exhaustion:

- Cap on new candidate peers per time window
- Candidate peers start at reps=0 and must earn
  reputation before being promoted to active sync
- Existing peers with established reputation are
  prioritized over new candidates

## Network Topology Over Time

```
t=0   A --- freechains.org        (bootstrap)

t=1   A --- freechains.org
       \--- B                     (B discovered via seed)

t=2   A --- B --- C               (C discovered via B)
       \--- freechains.org
```

The seed node becomes less important as the mesh grows.
Peers with high reputation become de facto hubs.

## Open Questions

1. How are peer addresses exchanged during sync?
   Dedicated commit? Sideband message? Out-of-band?
2. What thresholds trigger peer demotion or removal?

## Related Plans

- [metadata.md](metadata.md) — Data files catalog
- [replication.md](replication.md) — Sync mechanics
- [threats.md](threats.md) — Isolation attacks
