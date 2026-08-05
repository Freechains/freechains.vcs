require "freechains.common"

TMP   = "/tmp/freechains/"
GEN_0 = "genesis-0.lua"
GEN_1 = "genesis-1.lua"
GEN_2 = "genesis-2.lua"
GEN_3 = "genesis-3.lua"
GEN_4 = "genesis-4.lua"
ROOT  = TMP .. "/root/"
EXE   = "../src/freechains.lua --root " .. ROOT

SSH     = exec {
    cmd = "realpath ssh/",
} .. "/"
KEY1    = SSH .. "key1"
KEY2    = SSH .. "key2"
KEY3    = SSH .. "key3"
KEY4    = SSH .. "key4"
PUB1    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY1 .. ".pub",
}
PUB2    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY2 .. ".pub",
}
PUB3    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY3 .. ".pub",
}
PUB4    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY4 .. ".pub",
}
ENV     = ""
ENV_EXE = EXE

function TEST (name)
    print("  - " .. name .. "... ")
end

-- run a command expected to FAIL; assert the error msg if given; return it
function FAIL (t)
    local _, code, err = exec { err=false,
        cmd = t.cmd,
    }
    assert(code ~= 0, "should fail: " .. tostring(err))
    if t.err then
        assert(err == t.err, "should fail with: " .. tostring(err))
    end
    return err
end

-- consensus order of `chain` in the peer `exe`: the array (positions)
-- and the set (membership). Take whichever the assertion needs.
function ORDER (exe, chain)
    local out = exec {
        cmd = exe .. " chain '" .. chain .. "' list order",
    }
    local T = {}
    local S = {}
    for line in out:gmatch("[^\n]+") do
        T[#T+1] = line
        S[line] = true
    end
    return T, S
end

-- reps of the author `pub`. The `exec` call is parenthesized: it also
-- returns the exit code, which `tonumber` would take as the base.
function REPS (exe, chain, pub)
    return tonumber((exec {
        cmd = exe .. " chain '" .. chain .. "' reps author '" .. pub .. "'",
    }))
end

-- id -> commit: `CID` comes from freechains/common.lua; tests
-- pass `all=true` (begs live off-main) and the repo dir

-- the `Freechains` trailer of a commit: post, like, revoke or state
function TRAILER (dir, hash)
    return (exec {
        cmd = "git -C " .. dir ..
            " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash,
    }):match("%S+")
end
