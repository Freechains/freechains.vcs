-- TODO : review : post flow

local ssh = require "freechains.chain.ssh"

if not (ARGS.sign or ARGS.beg) then
    ERROR("chain post : requires --sign or --beg")
end

local pub = ARGS.sign and ssh.pub.key(ARGS.sign)
if ARGS.sign and not pub then
    ERROR("chain post : invalid sign key")
end

-- payload: name + blob hash only; enters the tree after `apply`
local file, blob
do
    if ARGS.inline then
        local rand = math.random(0, 9999999999)
        file = ARGS.file or "post-" .. CMD.now .. "-" .. rand .. ".txt"
    else
        assert(ARGS.file)
        file = ARGS.path:match("[^/]+$")    -- /tmp/hello.txt -> hello.txt
    end
    do
        local f = io.open(REPO .. file, "r")
        if f then
            f:close()
            ERROR("chain post : file already exists")
        end
    end
    if ARGS.inline then
        local f = io.open(REPO .. ".git/payload", "w")
        f:write(ARGS.text)
        f:close()
        blob = exec {
            cmd = "git -C " .. REPO .. " hash-object .git/payload",
        }
    else
        -- no -C: ARGS.path is relative to the CALLER's cwd
        blob = exec { stderr=false,
            cmd = "git hash-object " .. ARGS.path,
            err = "chain post : invalid path",
        }
    end
end

local aid = ACTION.pre {
    action = 'post',
    backs  = BACKS { "HEAD" },
    sign   = pub,
    time   = CMD.now,
    -- content is part of the identity: without it, same
    -- author + time + backs would collide (dedup, par.4)
    blob   = blob,
}

-- apply BEFORE the commit: failure leaves the repo untouched
do
    local T = {
        aid     = aid,
        -- TODO : remove : par.7 : peak folds over T.backs, no git
        parents = { (exec {
            cmd = "git -C " .. REPO .. " rev-parse HEAD",
        }) },
        sign    = pub,
        beg     = ARGS.beg,
    }
    local ok, err = apply(G, 'post', CMD.now, T)
    if not ok then
        ERROR("chain post : " .. err)
    end
    G.order[#G.order+1] = aid
end

-- one commit: payload + action file + state
do
    if ARGS.inline then
        os.rename(REPO .. ".git/payload", REPO .. file)
    else
        exec {
            cmd = "cp " .. ARGS.path .. " " .. REPO,
        }
    end
    exec {
        cmd = "git -C " .. REPO .. " add " .. file,
    }
    ACTION.pos(aid)
    WRITE(G)
    exec {
        cmd = "git -C " .. REPO .. " add .freechains/state.lua",
    }
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

if ARGS.beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/begs/beg-" .. aid .. " HEAD",
    }
    exec {
        cmd = "git -C " .. REPO .. " reset --hard HEAD~1",
    }
end

print(aid)
