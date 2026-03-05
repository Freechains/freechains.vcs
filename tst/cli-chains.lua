#!/usr/bin/env lua5.4

local FC = "./src/freechains"
local ROOT = "/tmp/fc-test-" .. os.time() .. "/"

function exec (cmd)
    local h = io.popen(cmd .. " 2>&1")
    local out = h:read("a"):match("^%s*(.-)%s*$")
    local ok, _, code = h:close()
    return out, (ok and 0 or code)
end

-- setup
local genesis_file = "/tmp/fc-test-genesis.lua"
local f = io.open(genesis_file, "w")
f:write('return {\n')
f:write('    version = {0, 11, 0},\n')
f:write('    type    = "#",\n')
f:write('}\n')
f:close()

local bad_file = "/tmp/fc-test-bad-genesis.lua"
f = io.open(bad_file, "w")
f:write('return "not a table"\n')
f:close()

print("chains add lua")

do -- success
    io.write("  success... ")
    local out, code = exec(
        FC .. " --root " .. ROOT
            .. " chains add mychain lua "
            .. genesis_file
    )
    assert(code == 0, "exit code: " .. tostring(code))
    assert(#out == 40, "hash length: " .. #out)
    assert(out:match("^%x+$"), "hash is hex")
    print("OK")
end

do -- genesis file exists
    io.write("  genesis file exists... ")
    local out = exec(
        "cat " .. ROOT
            .. "chains/mychain/.genesis.lua"
    )
    local genesis = load(out)()
    assert(type(genesis) == "table")
    assert(genesis.type == "#")
    print("OK")
end

do -- symlink points to hash dir
    io.write("  symlink points to hash dir... ")
    local target = exec(
        "readlink " .. ROOT .. "chains/mychain"
    )
    assert(target:match("^%x+/$"),
        "symlink target: " .. target)
    print("OK")
end

do -- bad genesis file
    io.write("  bad genesis file... ")
    local _, code = exec(
        FC .. " --root " .. ROOT
            .. " chains add bad lua " .. bad_file
    )
    assert(code ~= 0, "should fail")
    print("OK")
end

print()
print("chains rem (not implemented)")

do -- rem fails
    io.write("  rem fails... ")
    local _, code = exec(
        FC .. " --root " .. ROOT
            .. " chains rem mychain"
    )
    assert(code ~= 0, "should fail")
    print("OK")
end

print()
print("chains add args/remote (not implemented)")

do -- add args fails
    io.write("  add args fails... ")
    local _, code = exec(
        FC .. " --root " .. ROOT
            .. " chains add x args --type '#'"
    )
    assert(code ~= 0, "should fail")
    print("OK")
end

do -- add remote fails
    io.write("  add remote fails... ")
    local _, code = exec(
        FC .. " --root " .. ROOT
            .. " chains add x remote host hash"
    )
    assert(code ~= 0, "should fail")
    print("OK")
end

-- cleanup
os.execute("rm -rf " .. ROOT)
os.execute("rm -f " .. genesis_file .. " " .. bad_file)

print()
print("ALL PASSED")
