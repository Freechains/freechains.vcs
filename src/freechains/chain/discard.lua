--[[
-- `chain <alias> discard [--keep | --merge] <id>`
-- Drops an action and everything built on it (the hard-fork escape
-- hatch), or deletes a parked beg.
-- Inputs:
--  - ARGS.cid   [string]: the boundary cid (may be short)
--  - ARGS.keep  [boolean?]: cid is the last KEPT (or first DROPPED)
--  - ARGS.merge [boolean?]: cid is the first of a merged branch
--  - REPO [string]: the chain's repo dir
-- Outputs:
--  - stdout: the dropped cids, oldest first (or the beg cid)
--  - refs: HEAD reset to the kept tip; the dropped commits'
--    refs/states/ + refs/payloads/ deleted; stale begs deleted
-- Errors:
--  - "chain discard : invalid action" : not action, not in history, --keep beg
--  - "chain discard : unexpected merge" : cuts a sync merge (no --merge)
--  - "chain discard : expected merge" : --merge with no merge to cut
--  - "chain discard : partial branch" : --merge cid is not the first
--    of its branch
-- Callers:
--  - dispatch (chain/init.lua): ARGS.discard
--]]

-- Escape hatch for a hard fork: discard the stale local suffix (the
-- cid and everything after it), so the settled remote branch can be
-- received again.
-- Local only: no signing, no network, no reps.
-- Chain state lives in local snapshots (`refs/states/*`), keyed by
-- commit: the reset lands on a tip whose snapshot already exists.
--
-- One rule: discard drops the cid and everything BUILT ON it,
-- nothing else. What survives must have a single tip, where HEAD
-- lands.
--  - `discard <cid>`: cid is first DROPPED
--  - `discard --keep <cid>`: cid is the last KEPT (the same, named
--    by the action before)
--  - `discard --merge <cid>`: the drop cuts a sync merge in half (a
--    branch on its other side survives), so cid must be the FIRST of
--    its branch; HEAD lands on the other side. Required exactly
--    then, hence never with `--keep`: no kept action precedes the
--    first of a branch on that branch.
-- A sync merge that goes WHOLE (both sides built on the cid) is a
-- plain sequence: no flag.

--[[
  The model, in three rules:

  1. Discard drops the cid and everything built on it, nothing else.
     With --keep, the cid itself stays.
  2. --merge is required when that cuts a merge in half, meaning a
     dropped merge has a parent that survives. It is an error when
     given without need.
  3. What survives must have a single tip, where HEAD lands.
     Otherwise partial branch.

            F
          /   \
        b1     a1
         |     |
        b2     a2
          \   /
            M
            |
           c1   <-- HEAD

  ┌────────────────┬───────────┬────────────┬───────────────────┐
  │    command     │  dropped  │ merge cut  │      result       │
  │                │           │  in half?  │                   │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ discard c1     │ c1        │ no         │ lands on M        │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ --keep F       │ all above │ no, M goes │ lands on F        │
  │                │  F        │  whole     │                   │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ --keep b2      │ M, c1     │ yes        │ unexpected merge  │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ discard a1     │ a1, a2,   │ yes        │ unexpected merge  │
  │                │ M, c1     │            │                   │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ --merge a1     │ a1, a2,   │ yes        │ lands on b2       │
  │                │ M, c1     │            │                   │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ --merge a2     │ a2, M, c1 │ yes, tips  │ partial branch    │
  │                │           │ a1 and b2  │                   │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ --merge c1     │ c1        │ no         │ expected merge    │
  ├────────────────┼───────────┼────────────┼───────────────────┤
  │ --keep --merge │           │            │ refused at the    │
  │  anything      │           │            │ command line      │
  └────────────────┴───────────┴────────────┴───────────────────┘
]]

-- the cid may be abbreviated (`list dag` prints it so)
ARGS.cid = ACTION.full(ARGS.cid)

if not (ARGS.cid and ACTION.is(ARGS.cid)) then
    ERROR("chain discard : invalid action")
end

-- a beg is a post outside `main`, alone on its own cid-named ref:
-- nothing follows it, so discarding it is just deleting the ref
do
    local ref = "refs/begs/beg-" .. ARGS.cid
    local ok = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " show-ref --verify --quiet " .. ref,
    }
    if ok then
        -- a beg is not in `main`: there is nothing to keep up to
        if ARGS.keep then
            ERROR("chain discard : invalid action")
        end
        -- nor any merge to cut
        if ARGS.merge then
            ERROR("chain discard : expected merge")
        end
        exec {
            cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
        }
        print(ARGS.cid)
        os.exit(0)
    end
end

-- the commit must be part of our history (resolution already
-- proves it is an action)
do
    local ok = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. ARGS.cid .. " HEAD",
    }
    if not ok then
        ERROR("chain discard : invalid action")
    end
end

-- drops: the dropped set, the cid (unless `--keep`) and all built on
--        it, each mapped to its parents
--[[
            F
          /   \
        b1     a1   <-- cid
         |     |
        b2     a2
          \   /
            M
            |
           c1   <-- HEAD

  ┌──────────────────────┬───────────────────┐
  │       command        │       lists       │
  ├──────────────────────┼───────────────────┤
  │ rev-list a1..HEAD    │ c1, M, a2, b2, b1 │
  ├──────────────────────┼───────────────────┤
  │ with --ancestry-path │ c1, M, a2         │
  └──────────────────────┴───────────────────┘
]]

local drops = {
    --[[
    -- (commit -> parents, for `discard a1` above)
    c1 = { M },
    M  = { b2, a2 },
    a2 = { a1 },
    a1 = { F },          -- the cid itself: absent with `--keep`
    ]]
}
do
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --parents --ancestry-path " .. ARGS.cid .. "..HEAD",
    }
    if not ARGS.keep then
        out = out .. "\n" .. exec {
            cmd = "git -C " .. REPO .. " rev-list --parents -n 1 " .. ARGS.cid,
        }
    end
    for line in out:gmatch("[^\n]+") do
        local ps = {}
        for h in line:gmatch("%x+") do
            ps[#ps+1] = h
        end
        local c = table.remove(ps, 1)
        drops[c] = ps
    end
end

-- tips: the surviving parents of the dropped set (array, and each
--       hash also a key, so none repeats)
-- cut:  a dropped sync merge has a surviving parent, so the branch
--       on its other side stays (a merge that goes whole is not cut)
local tips, cut = {}, false
for c, ps in pairs(drops) do
    local act = (#ps < 2) or ACTION.is(c)
    for i, p in ipairs(ps) do
        -- a beg-attach like owns its beg post (2nd parent), which
        -- goes with it: not a survivor
        if (not drops[p]) and (not (act and i==2)) then
            cut = cut or (not act)
            if not tips[p] then
                tips[p] = true
                tips[#tips+1] = p
            end
        end
    end
end

-- `--merge` is the consent to cut a merge: required exactly then
if cut and (not ARGS.merge) then
    ERROR("chain discard : unexpected merge")
end
if ARGS.merge and (not cut) then
    ERROR("chain discard : expected merge")
end

-- where we land: the single tip of what survives. Two independent
-- tips could only stay together in a new merge, which discard never
-- builds: the cid is not the first of its branch
local tip
if #tips == 0 then
    tip = ARGS.cid      -- `--keep` the tip itself: nothing to drop
elseif #tips == 1 then
    tip = tips[1]
else
    tip = exec {
        cmd = "git -C " .. REPO .. " merge-base --independent " .. table.concat(tips, " "),
    }
    if select(2, tip:gsub("%x+", "")) ~= 1 then
        ERROR("chain discard : partial branch")
    end
end

-- the dropped range, oldest first
local range = {}
do
    local out = exec {
        cmd = "git -C " .. REPO .. " " ..
            "log --reverse --format='%H' " ..
            (tip .. "..HEAD"),
    }
    for h in out:gmatch("%x+") do
        range[#range+1] = h
    end
end

-- report what is about to be discarded: one cid per line, like
-- `list` (the range is `drops` plus the beg posts its likes attached)
for _, h in ipairs(range) do
    -- the dropped commit's state blob loses its anchor, so gc can
    -- reclaim it (state lives in refs/states/<cid>, keyed by commit)
    exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " update-ref -d refs/states/" .. h,
    }
    -- a sync merge has a snapshot but no payload, and is not reported
    if ACTION.is(h) then
        -- payloads go with them
        exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " update-ref -d refs/payloads/" .. h,
        }
        print(h)
    end
end

-- settled posts can be discarded: the hard-fork rule (settle by
-- consensus time) guards against a REMOTE reorder, never against a
-- deliberate local escape
exec {
    cmd = "git -C " .. REPO .. " update-ref HEAD " .. tip,
}

-- stale-beg cleanup: a beg is one commit (the post) on top of the
-- `main` it was created from. If that base is gone, the beg can no
-- longer attach to `main`, so discard it.
do
    local out = exec {
        cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname) %(objectname)'",
    }
    for refname, beg in out:gmatch("(%S+)%s+(%S+)") do
        local ok = exec { stderr=false, err=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. beg .. "~1 HEAD",
        }
        if not ok then
            exec {
                cmd = "git -C " .. REPO .. " update-ref -d " .. refname,
            }
        end
    end
end
