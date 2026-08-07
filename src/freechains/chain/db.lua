-- TODO : review : redesign : full file

-- persistent commit<->ID index (S11b/S11c): `.git/index.lua`
-- holds { tip, a2c, c2a }. Facts are immutable (a commit's tree
-- never changes), so entries are only ever added; membership is
-- NOT its question -- entries outlive resets and include begs
-- and voided commits, so reachability stays git's (checked per
-- query in get/destroy).
-- Steady state is incremental: writers append their own pair
-- (DB.add), sync walks only the fetched delta (DB.walk).
-- The full walk runs on cold start (no file, clone) or recovery
-- (dead tip after prune/gc).

local DB = {}

local IDX = nil

local function save ()
    local f = io.open(REPO .. ".git/index.lua", "w")
    f:write(serial {
        tip = IDX.tip,
        a2c = IDX.a2c,
        c2a = IDX.c2a,
    })
    f:close()
end

-- one `git log` pass over `range` fills both maps; false on a
-- bad range (dead tip)
local function walk (range)
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " log " .. range ..
            " --full-history --cc --name-only --diff-filter=A" ..
            " --format='C %H' -- .freechains/actions/",
    }
    if out == false then
        return false
    end
    local cid
    for line in out:gmatch("[^\n]+") do
        local h = line:match("^C (%x+)$")
        if h then
            cid = h
        else
            local aid = line:match("actions/(%x+)%.lua$")
            if aid then
                IDX.c2a[cid] = aid
                IDX.a2c[aid] = IDX.a2c[aid] or cid
            end
        end
    end
    return true
end

-- load once per process; catch up over `HEAD --not tip` when the
-- tip moved outside a writer (crash, external git)
local function lookup ()
    if IDX then
        return IDX
    end
    IDX = { a2c={}, c2a={} }
    local f = io.open(REPO .. ".git/index.lua", "r")
    if f then
        f:close()
        IDX = dofile(REPO .. ".git/index.lua")
    end
    local cur = exec {
        cmd = "git -C " .. REPO .. " rev-parse HEAD",
    }
    if IDX.tip ~= cur then
        if not (IDX.tip and walk("HEAD --not " .. IDX.tip)) then
            IDX.a2c, IDX.c2a = {}, {}
            assert(walk("HEAD"), "bug found : index rebuild")
        end
        IDX.tip = cur
        save()
    end
    return IDX
end

-- TODO : DONE : S11b : commit<->ID index replaces the per-commit
-- diff-tree lookup (was AID in chain/common.lua)
-- the aid a commit ADDED (.freechains/actions/<aid>.lua), or nil:
-- THE structural action test. No trailers -- the tree classifies
-- (par.5): action = one action file; merge = none, >=2 parents;
-- genesis = none, 0 parents; invalid = none, 1 parent.
-- Flat, unsharded: sharding waits for the S6a layout move.
-- Full hashes only: the index is keyed by them.
function DB.aid (cid)
    return lookup().c2a[cid]
end

-- the commit that ADDED action `aid`, or nil (fact, not
-- membership: callers needing "in MY history" must also check
-- ancestry vs HEAD)
function DB.cid (aid)
    return lookup().a2c[aid]
end

-- `aid`'s commit ONLY IF in my history, or nil. For aids from
-- the CLI (get/destroy): index facts outlive resets and include
-- begs/voided commits, so reachability is re-asked to git --
-- one exec, so keep it off sync's per-entry loops (reachable by
-- construction there).
function DB.own (aid)
    local cid = DB.cid(aid)
    if cid and exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. cid .. " HEAD",
    } then
        return cid
    end
    return nil
end

-- append a pair a writer just created (post/like commit; a beg
-- from its own ref). `ref` may be symbolic (HEAD, refs/begs/*):
-- resolved here, keeping the full-hash key invariant in one
-- place. `tip=true` when `ref` is the new HEAD.
function DB.add (aid, ref, tip)
    local cid = exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. ref,
    }
    local T = lookup()
    T.a2c[aid] = T.a2c[aid] or cid
    T.c2a[cid] = aid
    if tip then
        T.tip = cid
    end
    save()
end

-- widen over fetched commits before replay (sync recv)
function DB.walk (range)
    lookup()
    assert(walk(range), "bug found : index walk")
    save()
end

-- S15.1a: per-commit state snapshot, `.git/states/<cid>.lua`:
-- the state as of `ref` -- the fold over its OWN ancestors
-- (writer semantics). Write-only for now; readers swap in at
-- S15.1c/S15.2.
function DB.snap (ref, G)
    local cid = exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. ref,
    }
    exec {
        cmd = "mkdir -p " .. REPO .. ".git/states/",
    }
    local f = io.open(REPO .. ".git/states/" .. cid .. ".lua", "w")
    f:write(STATE(G))
    f:close()
end

-- record the tip the index now covers (sync recv end); no-op if
-- this run never touched the index
function DB.tip ()
    if IDX == nil then
        return
    end
    IDX.tip = exec {
        cmd = "git -C " .. REPO .. " rev-parse HEAD",
    }
    save()
end

return DB
