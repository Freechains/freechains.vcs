--[[
-- `chain <alias> post`
-- Mint a post action, accept it via pipeline, anchor its payload, move HEAD
-- (or park as a beg).
-- Inputs:
--  - ARGS.inline/ARGS.text [string?]: inline payload
--  - ARGS.file/ARGS.path   [string?]: payload file path
--  - ARGS.sign [string?]: ssh private key path
--  - ARGS.beg  [boolean?]: park on refs/begs/, HEAD untouched
--  - ARGS.now  [integer]: the action's TIME (commit DATE)
--  - G    [table]: state at HEAD; MUTATED by the pipeline
--  - HEAD [string]: the tip cid, the new post's parent
--  - REPO [string]: the chain's bare repo dir
-- Outputs:
--  - stdout: the new cid
--  - refs: payload blob at refs/payloads/<cid>; HEAD -> cid,
--    or refs/begs/beg-<cid> (--beg); state at refs/local/<cid>
-- Errors:
--  - "chain post : requires --sign or --beg" (gated chains only:
--    an open chain accepts an unsigned post, as `anonymous`)
--  - "chain post : invalid sign key"
--  - "chain post : invalid path"
--  - "chain post : <rules>" : refused by the pipeline
-- Callers:
--  - dispatch (chain/init.lua): ARGS.post
--]]

-- an OPEN chain has no gates, so an unsigned post needs no
-- sponsor: it lands in the chain, charged to the shared `anonymous`
-- account (`ACTION.apply` does the substitution)
if not (ARGS.sign or ARGS.beg or G.open) then
    ERROR("chain post : requires --sign or --beg")
end

-- a bad key fails EARLY and clean: nothing reaches git
if ARGS.sign and (not SSH.pub(ARGS.sign)) then
    ERROR("chain post : invalid sign key")
end

-- the payload lives OUTSIDE the commit: a loose blob, anchored by
-- `refs/payloads/<cid>`. The action's `blob` field is what binds
-- it: the cid transitively commits to the content

local bytes
if ARGS.inline then
    bytes = ARGS.text
else
    assert(ARGS.file)
    -- read in the caller's cwd: relative paths just work
    local f, why = io.open(ARGS.path, "rb")
    bytes = f and f:read("a")
    if f then
        f:close()
    end
    if not bytes then
        ERROR("chain post : invalid path", why and (why .. "\n"))
    end
end

-- save payload and commit
-- both UNANCHORED: rejection leaves them gc-able

local blob = STATE.put("blob", bytes)

local cid = ACTION.commit(
    (ARGS.sign and "chain post : invalid sign key") or nil,
    {
        parents = { HEAD },
        action  = 'post',
        blob    = blob,
        sign    = ARGS.sign,
    }
)

-- ONE pipeline for write and replay:
--  - re-reads the action from minted commit
--  - applies, orders, snapshots state

-- the pipeline reads the new commit and its parent: one cat-file
GIT.cats { cid, HEAD }

local refs = {}     -- the snapshot's ref, then the anchors: one call
local ok, err = pcall(ACTION.apply, G, cid, ARGS.beg, refs)
if not ok then
    ERROR("chain post : " .. err:gsub("^invalid %a+ : ", ""))
end

-- ACCEPTED: anchor payload, post

refs[#refs+1] = "update refs/payloads/" .. cid .. " " .. blob
if ARGS.beg then
    -- a beg parks on its own ref, outside `main`: HEAD never moves
    refs[#refs+1] = "update refs/begs/beg-" .. cid .. " " .. cid
else
    refs[#refs+1] = "update HEAD " .. cid
end
STATE.flush(refs)

print(cid)
