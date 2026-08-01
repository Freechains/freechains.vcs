local ssh = require "freechains.chain.ssh"

if not (ARGS.sign or ARGS.beg) then
    ERROR("chain post : requires --sign or --beg")
end

-- commit post (content only, no state)
local hash
do
    local file
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
    exec {
        cmd = "git -C " .. REPO .. " add " .. file,
    }
    local msg = ARGS.why or "(empty message)"
    hash = commit_tree(msg, "post", ARGS.sign, "chain post : invalid sign key")
end

-- apply with real hash
do
    local T = {
        hash = hash,
        sign = ARGS.sign and ssh.pubkey(REPO, hash),
        beg  = ARGS.beg,
    }
    local ok, err = apply(G, 'post', CMD.now, T)
    if not ok then
        exec {
            cmd = "git -C " .. REPO .. " reset --hard HEAD~1",
        }
        ERROR("chain post : " .. err)
    end
    G.order[#G.order+1] = hash
end

-- commit state
do
    write(G)
    exec {
        cmd = "git -C " .. REPO .. " add .freechains/state/",
    }
    commit_tree("(empty message)", "state", nil, nil)
end

if ARGS.beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/begs/beg-" .. hash .. " HEAD",
    }
    exec {
        cmd = "git -C " .. REPO .. " reset --hard HEAD~2",
    }
end

print(hash)
