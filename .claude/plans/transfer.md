# Transfer: Git Security and Efficiency

## Overview

How git's transfer layer is hardened for Freechains:
blob rejection, DoS protection, and incremental sync.
All mechanisms work within standard git — no protocol
modifications.

## 1. Blob Reject List

Blobs with malicious or illegal content can be omitted
from transfer without breaking the repository.
Git's partial clone mechanism ("promised but missing
objects") supports this natively — the repo works
normally for all other files, only checkout of the
missing blobs fails.

Tree objects still reference the rejected blob SHAs,
so the DAG stays intact.

A wrapper around `git fsck` filters the reject list
SHAs without modifying the protocol:

```bash
git fsck 2>&1 | grep -v -f reject.list
```

### Open questions

- Where is the reject list stored? Per-chain or global?
- How is the reject list distributed among peers?
- Should rejected blobs be garbage-collected or kept
  as empty placeholders?

## 2. Malicious Node Protection

A malicious node can send infinite small blobs as a DoS
attack — each passes individual size filters but fills
the disk across multiple pushes.

### receive.maxInputSize (first line of defense)

The most effective defense is `receive.maxInputSize`,
which cuts the transfer mid-stream and discards
everything atomically — no objects are written to
`objects/`.

Note: this limits the **total pack size**, not
individual object size. A malicious node could send
many small objects within the limit per push, so the
attack becomes slower but not impossible.

### Object count limiting (second line of defense)

Limiting by count of new objects requires a
`pre-receive` hook, but the pack has already been
received when the hook runs — the bandwidth damage
is done. Blocking during transfer would require a
proxy that inspects the pack stream.

### Complementary defenses

- `receive.denyNonFastForwards` — prevents history
  rewriting via push
- Peer reputation (see [overlay.md](overlay.md)) —
  peers with repeated failures or rejected branches
  lose reputation and are eventually dropped

## 3. Incremental Sync via Binary Search

When a pull exceeds the receive size limit, the
receiver can navigate periodic tags (daily, weekly)
via binary search to find the most recent point that
fits within the limit — without modifying the protocol
and without trusting the sender for anything.
Each attempt is verified locally.

```
main fails → try tag 2023-01 → fails
           → try tag 2021-06 → ok
           → try tag 2022-03 → fails
           → ...
```

Converges in O(log n) attempts, where n is the number
of tags.
After finding the entry point, sync proceeds
incrementally until reaching main.

### Assumptions

- Tags must be **signed** (or at least present on the
  remote), otherwise the sender controls what the
  receiver navigates
- The receiver needs a way to estimate pack size before
  full download — `git ls-remote` + local
  `git rev-list --count` can approximate the delta
- The sender must publish periodic tags with sufficient
  granularity

## Related Plans

- [threats.md](threats.md) — T6a: object injection via
  fetch
- [consensus.md](consensus.md) — Fetch validation
  pipeline
- [replication.md](replication.md) — Sync workflow
- [overlay.md](overlay.md) — Peer reputation
