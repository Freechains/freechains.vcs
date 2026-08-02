C    = require "freechains.constants"
REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"
FC   = REPO .. ".freechains/"

function trailer (hash)
    local out = exec {
        cmd = "git -C " .. REPO ..
            " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash,
    }
    return out:match "(%S+)"
end

-- the git parents of `hash`: one step back in the DAG, no time
-- involved. Returns an array (empty for a root).
function parents (hash)
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --parents -1 " .. hash,
        -- $ git rev-list --parents -1 a1b2c3...
        -- a1b2c3... d4e5f6... 7890ab...  # merge: 2 parents
    }
    local ps = {}
    for h in out:gmatch("%x+") do
        ps[#ps+1] = h
    end
    table.remove(ps, 1)
    return ps
end

-- post/like/revoke ancestors of `hash`: `parents` recursed through
-- `state` (and `merge`) commits, which are plumbing the protocol does
-- not expose. Returns an array of hashes (dedup'd).
function backs (hash)
    local ret = {}
    local see = {}
    local function rec (h)
        for _, p in ipairs(parents(h)) do
            local k = trailer(p)
            if k=='post' or k=='like' or k=='revoke' then
                if not see[p] then
                    see[p] = true
                    ret[#ret+1] = p
                end
            elseif k=='state' or k=='merge' then
                rec(p)
            else
                error("bug found : invalid trailer")
            end
        end
    end
    rec(hash)
    return ret
end

-- Prepare the merge of `hash` into HEAD, for `checkout` + `commit` to
-- conclude. Returns the merged tree, or nil on a content conflict.
--
-- Not `git merge`: it insists on materialising every path it touches,
-- and a post revoked before it ever reached us has no bytes to write
-- -- no honest peer serves them -- so an ordinary sync would die on
-- perfectly valid history. `merge-tree` works from trees and hashes
-- alone, and an absent blob simply passes through by hash.
--
-- It touches neither index nor working tree, so its output is placed
-- by hand: MERGE_HEAD here, for the second parent `commit` picks up,
-- and the tree by the `checkout` the caller makes next.
function merge_tree (hash)
    local tree = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-tree --write-tree HEAD " .. hash,
    }
    if not tree then
        return nil
    end
    local f = io.open(REPO .. ".git/MERGE_HEAD", "w")
    f:write(hash .. "\n")
    f:close()
    return tree
end

-- Conclude a commit on HEAD (and on MERGE_HEAD too, if a merge is
-- pending) via plumbing rather than porcelain `git commit`:
-- `write-tree --missing-ok` tolerates an object missing elsewhere in
-- the tree (a future revoked/removed payload), which plain `commit`'s
-- internal `write-tree` call does not -- it fails the whole commit.
-- `sign`, if given, is a signing key path; `err`, if given, is the
-- ERROR message on signing failure (mirrors the `err=` each call site
-- previously passed straight to `exec` for the `git commit` this
-- replaces). Returns the new commit hash.
function commit (msg, kind, sign, err)
    local tree = exec { stderr=false,
        cmd = "git -C " .. REPO .. " write-tree --missing-ok",
    }

    local merge_head = REPO .. ".git/MERGE_HEAD"
    local mh_file = io.open(merge_head, "r")
    local parents = "-p HEAD"
    if mh_file then
        local mh = mh_file:read("l")
        mh_file:close()
        parents = parents .. " -p " .. mh
    end

    local s1, s2 = "", ""
    if sign then
        s1 = " -c user.signingkey=" .. sign .. " -c gpg.format=ssh"
        s2 = " -S"
    end

    local full_msg = exec { stderr=false,
        cmd = "printf '%s\\n' '" .. msg .. "' | git -C " .. REPO ..
              " interpret-trailers --trailer 'Freechains: " .. kind .. "'",
    }

    local hash = exec { stderr=false,
        cmd = CMD.git .. "git -C " .. REPO .. s1 .. " commit-tree " .. tree
              .. " " .. parents .. s2 .. " -m '" .. full_msg .. "'",
        err = err,
    }

    exec {
        cmd = "git -C " .. REPO .. " update-ref HEAD " .. hash,
    }

    if mh_file then
        exec {
            cmd = "rm -f " .. REPO .. ".git/MERGE_HEAD " ..
                  REPO .. ".git/MERGE_MODE " .. REPO .. ".git/MERGE_MSG",
        }
    end

    return hash
end

function write (G)
    local function f (V, file)
        local f = io.open(file, "w")
        f:write(serial(V))
        f:close()
    end

    f(G.authors, FC .. "state/authors.lua")
    f(G.posts,   FC .. "state/posts.lua")
    f(G.order,   FC .. "state/order.lua")
    f(G.now,     FC .. "state/now.lua")
end

-- Posts whose revoke sums may have moved this run: CANDIDATES to
-- re-check once everything has settled, never decisions taken now.
-- Filled by a plain `REVOKES[hash] = true` wherever a revoke-axis vote
-- is applied. All correctness lives in `revokes` below, which re-reads
-- the COMMITTED state and decides there -- so over-filling this is
-- harmless (a candidate that is not actually revoked is skipped) and
-- under-filling is the only real bug.
REVOKES = {}

-- Physically drop the payload -- the loose blob AND the working-tree
-- copy, then skip-worktree the path so neither resurrects it nor
-- breaks a future checkout/reset/merge -- of every REVOKES candidate
-- the COMMITTED state still says is revoked (260721-remove-blob.md,
-- "Local removal").
--
-- Deferred to the end of a command on purpose: a sum that dips
-- negative mid-replay and climbs back before the end must never
-- trigger a deletion (finality window). Reads `state/posts.lua` off
-- disk rather than taking a `G`, so it acts on what was actually
-- persisted, not on an in-memory table a later abort might roll back.
-- Re-entrant: a tree entry names its blob whether or not the object
-- still exists, and os.remove on a missing file is a no-op.
--
-- BOTH channels -- `is_revoked`, the same predicate `get.lua` hides
-- by. One rule, applied identically from every caller: if this node
-- calls a post revoked, it drops the payload.
--
-- Community revocation stays REVERSIBLE (reps.md:287-312) without
-- keeping the bytes locally. A post whose sum climbs back non-negative
-- simply rejoins the set the by-hash step re-requests on the next
-- sync, and returns like any other payload this node lacks. Local
-- retention was never the restore mechanism.
--
-- Evaluating ONCE here, on the final committed sum, is also what keeps
-- this order-independent: two peers replaying the same votes in any
-- order reach the same sum, hence the same decision.
--
-- CAVEAT: the return path only works while SOMEONE still serves the
-- bytes. Every honest peer drops on learning the revoke, so once they
-- have all synced, none can serve it back and no unrevoke can be cast
-- (the gate refuses: "blob unavailable"). Community revocation is
-- therefore reversible only in the window before peers converge --
-- see the plan's open items.
function revokes ()
    local posts = dofile(FC .. "state/posts.lua")
    for hash in pairs(REVOKES) do
        if is_revoked(posts[hash] or {}) then
            -- a post commit adds exactly one file (get.lua asserts the same)
            local file = assert((exec {
                cmd = "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. hash,
            }):match("(%S+)"), "bug found")

            local blob = exec {
                cmd = "git -C " .. REPO .. " rev-parse " .. hash .. ":" .. file,
            }

            os.remove(REPO .. ".git/objects/" .. blob:sub(1,2) .. "/" .. blob:sub(3))
            os.remove(REPO .. file)
            exec { err=false,
                cmd = "git -C " .. REPO .. " update-index --skip-worktree " .. file,
            }
        end
    end
    REVOKES = {}
end

-- Step 2 of a sync. Step 1 pulls a FILTERED pack -- commits and trees
-- only, so a peer holding a removed payload can still serve it -- and
-- this pulls the payloads themselves, BY EXPLICIT HASH, from that same
-- peer. It runs in sequence right after, not at read time: a sync is
-- not finished until this has run, so a completed sync still leaves
-- this node holding every live payload. Replication is unchanged;
-- what changed is that it takes two round trips instead of one (three
-- when the remote's own revoked set has to be read first, below).
--
-- Deliberately NOT git's promisor machinery (which `--filter` sets up
-- behind our back, and which `sync.lua` strips): that binds one remote
-- URL, while Freechains syncs whatever peer it was pointed at, and it
-- would lazily re-fetch on any read -- including a read of something
-- this node revoked on purpose.
--
-- A fetch REQUEST is all-or-nothing: one absent hash sinks the whole
-- batch and its available siblings are NOT delivered. So: one
-- optimistic batch (the fast path, a single round trip when nothing
-- in the set is revoked), and only on failure a per-blob retry, where
-- the available ones land and the absent ones fail individually.
function payloads (url)
    -- FETCH_HEAD as well as --all: this runs BEFORE the replay moves
    -- any ref, so the commits just fetched are reachable only from
    -- there, and their payloads are exactly what we came for.
    local missing = missing_objects(REPO, "--all FETCH_HEAD")
    if #missing == 0 then
        return
    end

    -- Never ask for what WE already call revoked: no honest peer serves
    -- it, and asking would sink the optimistic batch on every sync.
    local ok_absent = revoked_blobs(REPO, "HEAD")

    -- Nor for what the REMOTE revoked -- which is most of the point,
    -- since the votes arriving right now are exactly the ones we have
    -- not replayed yet, and the peer is right not to serve what they
    -- condemn. Its `state/posts.lua` says so, but that is a blob too,
    -- filtered out of step 1, so pull it first and ALONE: one small
    -- extra round trip buys the whole batch below, which would
    -- otherwise sink on the first such payload and degrade into one
    -- round trip per object. Its hash is a tree lookup, no bytes
    -- needed. A peer refusing THIS is caught by the check at the end.
    do
        local state = exec { stderr=false, err=false,
            cmd = "git -C " .. REPO ..
                  " rev-parse FETCH_HEAD:.freechains/state/posts.lua",
        }
        for _, h in ipairs(missing) do
            if h == state then
                fetch_objects(REPO, url, {state})
                break
            end
        end
        for b in pairs(revoked_blobs(REPO, "FETCH_HEAD")) do
            ok_absent[b] = true
        end
    end

    local want = {}
    for _, h in ipairs(missing) do
        if not ok_absent[h] then
            want[#want+1] = h
        end
    end

    fetch_objects(REPO, url, want)

    -- Onboarding cannot half-succeed. Anything still absent that nobody
    -- calls revoked means this peer could not serve content it should:
    -- it is not honest, so fail before any ref moves and let another
    -- peer be tried.
    for _, h in ipairs(missing_objects(REPO, "--all FETCH_HEAD")) do
        if not ok_absent[h] then
            ERROR("chain sync : peer lacks payload : " .. h)
        end
    end
end

-- posts hashes in a stable order: (time, hash); consolidated posts
-- (time == nil) sort last, then lexicographically by hash. Makes the
-- discount/consolidation scans deterministic across OS processes.
local function ordered (posts)
    local hs = {}
    for h in pairs(posts) do
        hs[#hs+1] = h
    end
    table.sort(hs, function (a, b)
        local ta = posts[a].time or math.huge
        local tb = posts[b].time or math.huge
        if ta == tb then
            return a < b
        else
            return ta < tb
        end
    end)
    return hs
end

-- a commit's OWN author date, which says nothing about its ancestors:
-- a post carries the state file of the commit BEFORE it, so its own
-- stamp lives nowhere else.
local function TIME (hash)
    return assert(tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. hash,
    })))
end

-- the peak RECORDED in a commit's tree (`state/now.lua`): the newest
-- time among all of its ancestors. Derived, never trusted: `replay` in
-- sync.lua checks every stored value against its parents' before using
-- it. Only `state` commits are current -- a post/like may just ADD
-- files, so its tree still holds the previous state commit's value.
function PEAK (hash)
    local src = exec {
        cmd = "git -C " .. REPO .. " show " .. hash .. ":.freechains/state/now.lua",
    }
    return load(src)()
end

-- the peak COMPUTED over a set of commits: the peak each one recorded,
-- or its own time if newer (a post's tree still holds the PREVIOUS
-- peak, so its stamp lives nowhere else). The only place the fold
-- happens: `PEAKS(parents(h))` is the newest time causally preceding
-- `h`, the value a state commit must record, so writer and verifier
-- share the formula. Asserts on an empty set: only a root has no
-- parents, and no path takes a root this far.
function PEAKS (hs)
    local mx = nil
    for _, h in ipairs(hs) do
        local t = math.max(TIME(h), PEAK(h))
        mx = math.max(mx or t, t)
    end
    return assert(mx)
end

function apply (G, kind, time, T)
    local mutate = (kind ~= 'reps')

    -- TIME: monotonicity, discount, consolidation
    do
        -- causal freshness: a commit may sit at most `time.diff` below
        -- everything that precedes it. Read from the DAG, so it does not
        -- depend on the order a replay applies commits in (consensus order
        -- is not chronological order).
        if mutate then
            local up = PEAKS(parents(T.hash))
            if time < up-C.time.diff then
                return false, "too old"
            end
        end

        -- discount scan (maybe signed at same G.now)
        local sign = (mutate and T.sign) or nil
        if time>G.now or sign then
            for _, hash in ipairs(ordered(G.posts)) do
                local entry = G.posts[hash]
                if entry.maturity == "00-12" then
                    local subs = {}
                    for h2, other in pairs(G.posts) do
                        if other.author and other.time and other.time>entry.time then
                            subs[other.author] = true
                        end
                    end
                    if sign then
                        subs[sign] = true
                    end

                    local cur = 0
                    for a in pairs(subs) do
                        cur = cur + math.max(0, (G.authors[a] and G.authors[a].reps) or 0)
                    end
                    local tot = 0
                    for _, v in pairs(G.authors) do
                        tot = tot + math.max(0, v.reps)
                    end

                    local ratio = (tot>0 and cur/tot) or 0
                    local discount = C.time.half * math.max(0, 1 - 2*ratio)

                    if time >= entry.time + discount then
                        -- signed beg?
                        if entry.author then
                            G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                        end
                        entry.maturity = "12-24"
                    end
                end
            end
        end

        -- consolidation scan
        if time > G.now then
            for _, hash in ipairs(ordered(G.posts)) do
                local entry = G.posts[hash]
                if entry.maturity == "12-24" then
                    if time >= entry.time+C.time.full then
                        if entry.author then
                            local last = G.authors[entry.author].time
                            if time-last >= C.time.full then
                                G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                                G.authors[entry.author].time = last + C.time.full
                                entry.maturity = nil
                                entry.time  = nil
                            end
                        else
                            -- authorless (unsigned beg): consolidate, no credit
                            entry.maturity = nil
                            entry.time  = nil
                        end
                    end
                end
            end
        end

        if time > G.now then
            G.now = time
        end
    end

    if mutate then
        if kind == 'post' then
            -- validation
            assert(T.sign or T.beg)
            if T.sign then
                if T.beg then
                    local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                    if reps > 0 then
                        return false, "--beg error : author has sufficient reputation"
                    end
                else
                    local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                    if reps <= 0 then
                        return false, "insufficient reputation"
                    end
                end
            end

            -- mutation
            G.posts[T.hash] = {
                author   = T.sign,
                time     = time,
                maturity = (T.beg and 'beg') or (T.sign and '00-12') or 'beg',
                reps     = 0,
                revoke   = { author=0, others=0 },
            }
            if T.sign then
                G.authors[T.sign] = G.authors[T.sign] or { reps=0 }
                if not T.beg then
                    G.authors[T.sign].reps = G.authors[T.sign].reps - C.reps.cost
                    G.authors[T.sign].time = G.authors[T.sign].time or time
                        -- do not set for beg, bc not available to others
                end
            end

        elseif kind=='like' or kind=='revoke' then
            -- validation
            assert(T.sign, "bug found")
            if math.type(T.n)~='integer' or T.n==0 then
                return false, "invalid number : expects non-zero integer"
            end
            if (T.post and T.author) or (not T.post and not T.author) then
                return false, "invalid target : expects 'post' or 'author'"
            end
            -- revoke/unrevoke are post-only
            if kind=='revoke' and (not T.post) then
                return false, "invalid target : expects 'post'"
            end
            if T.post and (not G.posts[T.post]) then
                return false, "invalid target : post not found"
            end

            -- author self-revoke (right to be forgotten) is free and ungated
            local self_revoke = (
                kind=='revoke' and T.n<0 and G.posts[T.post].author==T.sign
            )

            -- must afford the full vote magnitude (no debt); self-revoke is free
            local reps = (G.authors[T.sign] and G.authors[T.sign].reps) or 0
            if (not self_revoke) and reps<math.abs(T.n) then
                return false, "insufficient reputation"
            end

            -- mutation
            if not self_revoke then
                G.authors[T.sign].reps = reps - math.abs(T.n)
            end
            local n = T.n * (100 - C.like.tax) // 100
            if T.post then
                local a = G.posts[T.post].author
                if not (self_revoke or (kind=='revoke' and T.n>0)) then
                    if a then
                        G.authors[a] = G.authors[a] or { reps=0 }
                        G.authors[a].reps = G.authors[a].reps + n//C.like.split
                    else
                        assert(T.beg)
                    end
                    G.posts[T.post].reps = G.posts[T.post].reps + n//C.like.split
                end

                -- revoke axis: sum the signed magnitude T.n (revoke n<0,
                -- unrevoke n>0). A positive `like` also counts as an
                -- `unrevoke` (the converse is false: a `dislike` never
                -- revokes). Author self-revoke feeds the absolute
                -- `author` channel; everyone else the `others` channel.
                if kind=='revoke' or T.n>0 then
                    local author = G.posts[T.post].author
                    local r = G.posts[T.post].revoke or { author=0, others=0 }
                    G.posts[T.post].revoke = r
                    if kind=='revoke' and author and T.sign==author then
                        r.author = r.author + T.n
                    else
                        r.others = r.others + T.n
                    end
                end

                if T.beg then
                    G.posts[T.post].maturity = "00-12"
                    G.posts[T.post].time = time
                    if a then
                        G.authors[a].time = G.authors[a].time or time
                    end
                end
            else
                G.authors[T.author] = G.authors[T.author] or { reps=0 }
                G.authors[T.author].reps = G.authors[T.author].reps + n
            end
        end
    end

    -- cap all authors at max
    for k, v in pairs(G.authors) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end

    return true
end
