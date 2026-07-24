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

### The divergence is representational, not semantic

Consolidating a different post does NOT change reps: consolidation
always does `author.reps += cost` once and `author.time += full` once,
regardless of which of the author's posts is cleared.

| quantity                 | peer B            | peer X            |
|--------------------------|-------------------|-------------------|
| author reps              | +1                | +1 (same)         |
| author `time`            | +24h              | +24h (same)       |
| consensus ordering       | unaffected        | unaffected        |
| `posts.lua` bytes        | post P consolidated | post Q consolidated |

It is also transient: on the next 24h step each peer consolidates its
*remaining* post, so both posts consolidate on both sides and reps fully
converge.

The only thing it breaks is the sync **exact-state check**
(`git diff --quiet HEAD -- .freechains/state/`, `sync.lua:362`), which
demands the receiver's re-derived `posts.lua` match the sender's
committed bytes verbatim. Two honest peers → same reps, different bytes
→ rejected.

We fix the derivation (make order stable) rather than relax the check:
the exact-match check is what proves a remote did not tamper with
state, so it stays strict.

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

## Next step (explicit — start here on the other machine)

All in `src/freechains/chain/common.lua`, inside `apply()`.

### 1. Add a deterministic key-order helper (near top of file)

```lua
-- posts hashes in a stable order: (time, hash); consolidated posts
-- (time == nil) sort last, then lexicographically by hash
local function ordered (posts)
    local hs = {}
    for h in pairs(posts) do
        hs[#hs+1] = h
    end
    table.sort(hs, function (a, b)
        local ta = posts[a].time or math.huge
        local tb = posts[b].time or math.huge
        if ta ~= tb then
            return ta < tb
        end
        return a < b
    end)
    return hs
end
```

### 2. Consolidation scan (currently `common.lua:119`)

Replace the outer loop header:

```lua
-- from:
for hash, entry in pairs(G.posts) do
-- to:
for _, hash in ipairs(ordered(G.posts)) do
    local entry = G.posts[hash]
```

Body unchanged. This makes the per-author 24h gate consolidate the
**oldest** eligible post first, identically on every peer.

### 3. Discount scan (currently `common.lua:82`)

Same substitution on its outer `for hash, entry in pairs(G.posts)` loop
(defensive: order is only a tiebreak there, but keep it stable). The
inner `subs` loop at `common.lua:85` reads posts into a set and does not
need ordering.

### 4. Verify

```
make tests          # full suite must stay green
./guide.sh          # Bob's `day 1` send must now be ACCEPTED,
                    # and the Hard Forks section must complete
```

- `guide.sh` needs `git`, `lua5.4`, and free ports 10000/10002; it
  kills stale daemons on enter.
- Note: `guide.sh` uses `sleep` and background `git daemon`, so run it
  in a real shell, not a restricted sandbox.

## Checklist

- [x] Diagnose (consolidation scan `pairs()` order; evidence captured)
- [x] Add `ordered()` helper in `common.lua`
- [x] Convert consolidation scan (`common.lua:119`) to `ordered()`
- [x] Convert discount scan (`common.lua:82`) to `ordered()`
- [x] `make tests` green
- [x] `./guide.sh`: `day 1` send accepted, Hard Forks completes

## References

- [reps.md](reps.md) — reputation, 12h/24h maturation
- [threats.md](threats.md) — T4b 12h maturation divergence
- [260721-send-now.md](260721-send-now.md) — `-o now` forwarding (the
  fix that exposed this by making the send path time-deterministic)
