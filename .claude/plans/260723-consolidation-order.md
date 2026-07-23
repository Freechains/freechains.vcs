# Consolidation Scan: Non-Deterministic `pairs()` Order

## Symptom

`sync send` of a new post is rejected by the receiver with:

```
ERROR : chain sync : remote state mismatch
```

Surfaced while running the README guide end to end (`guide.sh`):
Bob's `day 1` post, sent to the hub, is rejected even though it is a
plain fast-forward on top of a merge both peers already share.

## Not the cause

Ruled out during diagnosis:

| suspect                        | verdict                                   |
|--------------------------------|-------------------------------------------|
| `-o now` push-option fix       | correct; cured the earlier `too old`      |
| send-now vs post-now mismatch  | no — fails even when they are equal        |
| branch fork-back (`oct` old)   | no — `B tip == X tip`, `oct` is the merge |
| daemon transport               | no — an equivalent path `recv` also races |

## Root cause

`apply()` in `common.lua` has two scans that iterate posts with an
unordered `pairs(G.posts)`:

- discount scan, `common.lua:82`
- consolidation scan, `common.lua:119`

The consolidation scan gates to **one consolidation per author per 24h**:

```lua
for hash, entry in pairs(G.posts) do          -- UNORDERED
    if entry.maturity == "12-24" then
        if time >= entry.time+C.time.full then
            if entry.author then
                local last = G.authors[entry.author].time
                if time-last >= C.time.full then
                    ... reps += cost
                    G.authors[entry.author].time = last + C.time.full
                    entry.maturity = nil
                    entry.time  = nil
                end
            end
        end
    end
end
```

When one author holds **two or more posts** that cross their 24h
boundary in the same `apply`, the gate lets only the **first-visited**
one consolidate (it advances `author.time`, so the rest fail
`time-last >= full` this pass). Which post that is depends on Lua
table iteration order, which differs between OS processes.

Two peers deriving the same state in different processes therefore
disagree on *which* post consolidated. The receiver's re-derivation no
longer matches the sender's committed `posts.lua` → `remote state
mismatch`.

## Evidence

Guide state: Alice posts `Hello`/`I am here`/`Sync me` (t = +10/+20/+30),
all maturing around Bob's `day 1` (fork + 24h). The rejected-send diff
(receiver re-derived vs sender committed):

```
posts.lua
  64b110e "I am here" (t=+20):  sender=consolidated   receiver=12-24
  bc0149f "Sync me"   (t=+30):  sender=12-24          receiver=consolidated
```

Same author, two eligible posts, opposite choice per process.

The discount scan (`common.lua:82`) is the same class of hazard: it
also walks `pairs(G.posts)` and, in the inner `subs` loop, reads other
posts' state — order could affect results when several `00-12` posts
mature in one apply.

## Fix

Iterate both scans over posts in a **deterministic order** so every
peer consolidates the same post.

| file          | place                       | change                                   |
|---------------|-----------------------------|------------------------------------------|
| `common.lua`  | consolidation scan (l.119)  | iterate a sorted hash list, not `pairs`  |
| `common.lua`  | discount scan (l.82)        | same deterministic ordering (defensive)  |

Ordering options:

- **by hash** — absolute determinism, minimal assumptions.
- **by `(time, hash)`** — also deterministic, and gives FIFO
  ("oldest matured post consolidates first"), which is the more
  intuitive semantics. `12-24` posts still carry `time` during the
  scan, so this key is available.

Recommendation: `(time, hash)` for the consolidation scan (FIFO), hash
for the discount scan (order is only a tiebreak there).

Shared helper: a `sorted_hashes(G.posts, key)` that returns hashes in
the chosen order; both scans loop over it.

## Scope note

Pre-existing latent bug, independent of the 7-day rule and the `-o now`
work. It only manifests when a single author has multiple posts
crossing the 24h boundary within one `apply`, and two peers derive the
state in separate processes.

## Pending

- [x] Diagnose (consolidation scan `pairs()` order; evidence captured)
- [ ] Add `sorted_hashes` helper in `common.lua`
- [ ] Convert consolidation scan to sorted iteration
- [ ] Convert discount scan to sorted iteration
- [ ] Re-run `guide.sh`: `day 1` send accepted

## References

- [reps.md](reps.md) — reputation, 12h/24h maturation
- [threats.md](threats.md) — T4b 12h maturation divergence
- [260721-send-now.md](260721-send-now.md) — `-o now` forwarding (the
  fix that exposed this by making the send path time-deterministic)
