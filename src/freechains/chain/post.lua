local ssh = require "freechains.chain.ssh"

if not (ARGS.sign or ARGS.beg) then
    ERROR("chain post : requires --sign or --beg")
end

-- the writer's own pubkey, read from the `.pub` file BEFORE the
-- commit: a bad key fails early, nothing enters the tree
local pub = nil
if ARGS.sign then
    pub = ssh.pub.key(ARGS.sign)
    if not pub then
        ERROR("chain post : invalid sign key")
    end
end

-- commit post (content only, no state)

local aid
local file
do
    if ARGS.inline then
        local text = ARGS.text
        local rand = math.random(0, 9999999999)
        file = ARGS.file or "post-" .. CMD.now .. "-" .. rand .. ".txt"
        local path = REPO .. "/" .. file
        do
            local f = io.open(path, "r")
            if f then
                f:close()
                ERROR("chain post : file already exists")
            end
        end
        do
            local f = io.open(path, "w")
            f:write(text)
            f:close()
        end
    else
        assert(ARGS.file)
        file = ARGS.path:match("[^/]+$")
        do
            local f = io.open(REPO .. "/" .. file, "r")
            if f then
                f:close()
                ERROR("chain post : file already exists")
            end
        end
        exec { stderr=false,
            cmd = "cp " .. ARGS.path .. " " .. REPO .. "/",
            err = "chain post : invalid path",
        }
    end
    -- action file: self-description; minted BEFORE the commit
    -- (`pos` places it only after `apply` accepts)
    aid = ACTION.pre {
        action = 'post',
        backs  = ACTION.backs { "HEAD" },
        sign   = pub,
        time   = tonumber(CMD.now),
        blob   = exec {
            cmd = "git -C " .. REPO .. " hash-object " .. REPO .. "/" .. file,
        },
    }
end

-- apply BEFORE the commit: a rejected post leaves nothing
-- but the unstaged payload, removed right here
do
    local T = {
        aid     = aid,
        parents = { "HEAD" },
        sign    = pub,
        beg     = ARGS.beg,
    }
    local ok, err = apply(G, 'post', CMD.now, T)
    if not ok then
        os.remove(REPO .. "/" .. file)
        ERROR("chain post : " .. err)
    end
    G.order[#G.order+1] = aid
end

exec {
    cmd = "git -C " .. REPO .. " add " .. file,
}
ACTION.pos(aid)

do
    local s1, s2 = "", ""
    if ARGS.sign then
        s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=ssh"
        s2 = " -S"
    end
    local msg = ARGS.why or "(empty message)"
    exec { stderr=false,
        cmd = CMD.git .. "git -C " .. REPO .. s1 .. " commit" .. s2 .. " -m '" .. msg .. "'",
        err = "chain post : invalid sign key",
    }
end

-- snapshot state at the new tip (the action commit itself)
STATE.write(G, true, "HEAD")

if ARGS.beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/begs/beg-" .. aid .. " HEAD",
    }
    exec {
        cmd = "git -C " .. REPO .. " reset --hard HEAD~1",
    }
end

print(aid)
