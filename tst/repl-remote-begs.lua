#!/usr/bin/env lua5.4

-- begs over raw git, through git-daemon: refs/begs/* are plain
-- commits fetched by refspec and merged with stock git. CLI begs
-- happen while HEAD still has snapshots (raw merges leave none),
-- so the raw merge mechanics run LAST.

require "tests"

local ROOT_A = ROOT .. "/repl-remote-begs/A/"
local ROOT_B = ROOT .. "/repl-remote-begs/B/"
local ROOT_C = ROOT .. "/repl-remote-begs/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root=" .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root=" .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root=" .. ROOT_C

local REPO_A = ROOT_A .. "/chains/#test/"
local REPO_B = ROOT_B .. "/chains/#test/"
local REPO_C = ROOT_C .. "/chains/#test/"

exec {
    cmd = "mkdir -p " .. ROOT_A .. "/chains",
}
exec {
    cmd = "mkdir -p " .. ROOT_B .. "/chains",
}
exec {
    cmd = "mkdir -p " .. ROOT_C .. "/chains",
}

local PORT_A = 19418
local PORT_B = 19419
local PORT_C = 19420

local URL_A  = "git://127.0.0.1:" .. PORT_A .. "/"
local URL_B  = "git://127.0.0.1:" .. PORT_B .. "/"
local URL_C  = "git://127.0.0.1:" .. PORT_C .. "/"

local PID_A  = ROOT_A .. "/daemon.pid"
local PID_B  = ROOT_B .. "/daemon.pid"
local PID_C  = ROOT_C .. "/daemon.pid"

local function daemon_start (exe, port, pid)
    exec {
        cmd = exe .. " daemon --hub --port=" .. port .. " --" .. " --listen=127.0.0.1" .. " --pid-file=" .. pid .. " --reuseaddr" .. " --detach",
    }
end

local function daemon_stop (pid)
    local f = io.open(pid)
    if f then
        local pid = f:read("a"):match("%d+")
        f:close()
        if pid then
            os.execute("kill " .. pid .. " 2>/dev/null")
        end
    end
end

daemon_start(EXE_A, PORT_A, PID_A)
daemon_start(EXE_B, PORT_B, PID_B)
daemon_start(EXE_C, PORT_C, PID_C)
os.execute("sleep 0.3") -- starting up daemons

local _ <close> = setmetatable({}, {__close=function()
    daemon_stop(PID_A)
    daemon_stop(PID_B)
    daemon_stop(PID_C)
end})

-- HOST A: create chain + beg
local CHAIN_HASH

do
    print("==> Host A: create chain + beg")

    do
        TEST "chain created"
        CHAIN_HASH = exec {
            cmd = EXE_A .. " chains add '#test' init " .. GEN_0,
        }
        assert(#CHAIN_HASH == 41, "hash: " .. CHAIN_HASH)
        assert(CHAIN_HASH:match("^#%x+$"), "not hex")
    end

    do
        TEST "beg on A"
        local out = exec {
            cmd = EXE_A .. " chain '#test' post inline 'post from A' --beg",
        }
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end
end

-- HOST B: clone chain (begs included) + beg
do
    print("==> Host B: clone chain (begs included)")

    do
        TEST "clone succeeds"
        exec {
            cmd = EXE_B .. " chains add '#test' clone '" .. URL_A .. "#test/'",
        }
    end

    do
        TEST "B has same genesis"
        local gen_a = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --max-parents=0 HEAD",
        }
        local gen_b = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --max-parents=0 HEAD",
        }
        assert(gen_a == gen_b, "genesis mismatch")
    end

    -- no manual fetch: the clone itself must carry refs/begs/*
    do
        TEST "B has A's beg ref"
        local a = exec {
            cmd = "git -C " .. REPO_A .. " for-each-ref refs/begs/ --format='%(objectname)'",
        }
        local b = exec {
            cmd = "git -C " .. REPO_B .. " for-each-ref refs/begs/ --format='%(objectname)'",
        }
        assert(a == b, "beg hashes differ: " .. a .. " vs " .. b)
    end

    do
        TEST "beg on B"
        local out = exec {
            cmd = EXE_B .. " chain '#test' post inline 'post from B' --beg",
        }
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end
end

-- BIDIRECTIONAL: exchange beg refs by raw fetch
do
    print("==> Bidirectional beg sync")

    do
        TEST "A fetches begs from B"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " fetch '" .. URL_B .. "#test/' refs/begs/*:refs/begs/*",
        }
        assert(code == 0, "fetch failed")

        TEST "B fetches begs from A"
        local _, code = exec {
            cmd = "git -C " .. REPO_B .. " fetch '" .. URL_A .. "#test/' refs/begs/*:refs/begs/*",
        }
        assert(code == 0, "fetch failed")
    end

    do
        TEST "A and B have same beg refs"
        local a = exec {
            cmd = "git -C " .. REPO_A .. " for-each-ref refs/begs/ --sort=refname --format='%(refname) %(objectname)'",
        }
        local b = exec {
            cmd = "git -C " .. REPO_B .. " for-each-ref refs/begs/ --sort=refname --format='%(refname) %(objectname)'",
        }
        assert(a == b, "beg refs differ")
    end

    do
        TEST "A begs again"
        local out = exec {
            cmd = EXE_A .. " chain '#test' post inline 'second from A' --beg",
        }
        assert(#out == 40, "hash: " .. out)

        TEST "B begs again"
        local out = exec {
            cmd = EXE_B .. " chain '#test' post inline 'second from B' --beg",
        }
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "exchange again: 4 beg refs each, equal"
        exec {
            cmd = "git -C " .. REPO_A .. " fetch '" .. URL_B .. "#test/' refs/begs/*:refs/begs/*",
        }
        exec {
            cmd = "git -C " .. REPO_B .. " fetch '" .. URL_A .. "#test/' refs/begs/*:refs/begs/*",
        }
        local a = exec {
            cmd = "git -C " .. REPO_A .. " for-each-ref refs/begs/ --sort=refname --format='%(refname) %(objectname)'",
        }
        local b = exec {
            cmd = "git -C " .. REPO_B .. " for-each-ref refs/begs/ --sort=refname --format='%(refname) %(objectname)'",
        }
        assert(a == b, "beg refs differ")
        local count = 0
        for _ in a:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 4, "expected 4 beg refs, got: " .. count)
    end
end

-- UNRELATED HISTORIES: independent chain, fetch beg, merge fails
do
    print("==> Unrelated histories rejected")

    local h = exec {
        cmd = EXE_C .. " chains add '#test' init " .. GEN_0,
    }
    assert(h ~= CHAIN_HASH, "should differ")

    do
        TEST "fetch begs from A succeeds"
        local _, code = exec {
            cmd = "git -C " .. REPO_C .. " fetch '" .. URL_A .. "#test/' refs/begs/*:refs/begs/*",
        }
        assert(code == 0, "fetch should succeed")
    end

    do
        TEST "merge beg into unrelated HEAD fails"
        local ref = exec {
            cmd = "git -C " .. REPO_C .. " for-each-ref refs/begs/ --sort=refname --format='%(refname)'",
        }
        local first = ref:match("[^\n]+")
        FAIL {
            cmd = "git -C " .. REPO_C .. " merge --no-commit --no-ff " .. first,
        }
    end
end

-- MERGE MECHANICS (raw git, last: no CLI after these HEAD moves):
-- begs are ordinary commits; distinct action files never conflict
do
    print("==> Host A: merge begs into HEAD (raw git)")

    local refs = exec {
        cmd = "git -C " .. REPO_A .. " for-each-ref refs/begs/ --sort=refname --format='%(refname)'",
    }
    local ref1 = refs:match("[^\n]+")
    local ref2 = refs:match("[^\n]*\n([^\n]+)")

    do
        TEST "merge beg into HEAD (fast-forward)"
        exec {
            cmd = "git -C " .. REPO_A .. " merge --no-edit " .. ref1,
        }
        local count = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --count HEAD",
        }
        assert(count == "2", "count: " .. count)

        TEST "remove merged beg ref"
        exec {
            cmd = "git -C " .. REPO_A .. " update-ref -d " .. ref1,
        }
    end

    do
        TEST "merge second beg into HEAD (true merge, no conflict)"
        exec {
            cmd = "git -C " .. REPO_A .. " merge --no-edit " .. ref2,
        }
        local count = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --count HEAD",
        }
        assert(count == "4", "count: " .. count)

        TEST "remove merged beg ref"
        exec {
            cmd = "git -C " .. REPO_A .. " update-ref -d " .. ref2,
        }
    end

    do
        TEST "2 beg refs remain on A"
        local out = exec {
            cmd = "git -C " .. REPO_A .. " for-each-ref refs/begs/ --format='%(refname)'",
        }
        local count = 0
        for _ in out:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 2, "expected 2 beg refs, got: " .. count)
    end

    do
        TEST "both merged action files present in A"
        local count = exec {
            cmd = "ls " .. REPO_A .. "actions/*/*.lua | wc -l",
        }
        assert(count == "2", "expected 2 action files, got: " .. count)
    end
end

-- B pulls A's HEAD raw, then prunes begs already merged there
do
    print("==> Host B: pull + prune merged begs (raw git)")

    do
        TEST "B fetches HEAD from A"
        local _, code = exec {
            cmd = "git -C " .. REPO_B .. " fetch '" .. URL_A .. "#test/' main",
        }
        assert(code == 0, "fetch HEAD failed")

        TEST "B merges A's HEAD"
        exec {
            cmd = "git -C " .. REPO_B .. " merge --no-edit FETCH_HEAD",
        }
    end

    do
        TEST "B prunes merged begs"
        local refs = exec {
            cmd = "git -C " .. REPO_B .. " for-each-ref refs/begs/ --format='%(refname)'",
        }
        for ref in refs:gmatch("[^\n]+") do
            local _, code = exec { err=false,
                cmd = "git -C " .. REPO_B .. " merge-base --is-ancestor " .. ref .. " HEAD",
            }
            if code == 0 then
                exec {
                    cmd = "git -C " .. REPO_B .. " update-ref -d " .. ref,
                }
            end
        end

        TEST "B has 2 beg refs remaining"
        local out = exec {
            cmd = "git -C " .. REPO_B .. " for-each-ref refs/begs/ --format='%(refname)'",
        }
        local count = 0
        for _ in out:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 2, "expected 2 beg refs, got: " .. count)
    end
end

print("<== ALL PASSED")
