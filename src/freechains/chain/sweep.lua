
-- Reclaim what removal already unreferenced: a revoked payload
-- (`like` drops its `refs/payloads/` anchor) or an abandoned commit.
-- Local only: no signing, no network, no reps.
-- Payloads live outside the tree, anchored only by `refs/payloads/`,
-- so dropping the anchor is enough for the bytes to go here.
-- The abandoned COMMITS survive in the HEAD reflog until it expires:
-- they carry action files (metadata), never content.

-- stage 1: reclaim unreferenced blobs (revoked payloads, abandoned)

exec {
    cmd = "git -C " .. REPO .. " gc --prune=now --quiet",
    err = "chain sweep : git gc failed",
}

-- stage 2: prune snapshots more than `prune.actions` back in my
-- order -- the O(N^2) pile becomes O(keep*N).
-- The boundary comes from `order` (topological, so the last `keep`
-- entries are the ones to keep); `rev-list bound..HEAD` then keeps
-- that whole DAG region -- MERGES included, which `order` cannot
-- name. Everything else in the states dir (deeper actions, deeper
-- merges, abandoned orphans) is unreachable by P1/P2 and goes.

do
    local G = STATE.read(GIT.deref("HEAD"))
    local n = #G.order
    if n > C.prune.actions then
        local bound = ACTION.cid(G.order[n - C.prune.actions])
        local keep = { [GIT.deref("HEAD")] = true, [bound] = true }
        local out = exec {
            cmd = "git -C " .. REPO .. " rev-list " .. bound .. "..HEAD",
        }
        for h in out:gmatch("%x+") do
            keep[h] = true
        end
        local files = exec {
            cmd = "ls " .. REPO .. ".git/states/",
        }
        for f in files:gmatch("(%x+)%.lua") do
            if not keep[f] then
                os.remove(REPO .. ".git/states/" .. f .. ".lua")
            end
        end
    end
end
