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
    local _, code, err = exec { err = false,
        cmd = t.cmd,
    }
    assert(code ~= 0, "should fail: " .. tostring(err))
    if t.err then
        assert(err == t.err, "should fail with: " .. tostring(err))
    end
    return err
end
