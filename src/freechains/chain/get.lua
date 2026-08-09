require "freechains.chain.common"

local cid = ACTION.cid(ARGS.aid)
if not cid then
    ERROR("chain get : unknown post")
end
do
    local _, code = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. cid .. " HEAD",
    }
    if code ~= 0 then
        ERROR("chain get : unknown post")
    end
end

-- the action file, fetched ONCE: raw for metadata, parsed for
-- the payload branch's kind
local src = exec { trim=false,
    cmd = "git -C " .. REPO .. " cat-file blob " .. ARGS.aid,
}

local kind = assert(load(src))().action

-- the single tracked file in this commit (post payload or like Lua).
-- --cc reduces to the file(s) present in this commit but absent
-- from every parent — handles both regular commits and merges
-- (without --cc, diff-tree emits nothing for merge commits).
local function commit_file ()
    local files = exec {
        cmd = "git -C " .. REPO ..
        " diff-tree --cc --no-commit-id -r --name-only " .. cid ..
        " -- . ':!.freechains/actions'",    -- TODO : remove
    }
    assert(not files:match("\n%S"), "bug found")
    return files:match("^(%S+)")
end

if ARGS.payload then
    if kind ~= "post" then
        ERROR("chain get : unknown post")
    end

    if G.posts[ARGS.aid] and is_revoked(G.posts[ARGS.aid]) then
        ERROR("chain get : revoked post")
    end

    local file = commit_file()
    local out = exec { trim=false,
        cmd = "git -C " .. REPO .. " show " .. cid .. ":" .. file,
    }
    io.write(out)

elseif ARGS.metadata then
    -- the metadata IS the action file (serialized Lua)
    io.write(src)
end
