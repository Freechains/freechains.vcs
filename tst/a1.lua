#!/usr/bin/env lua
--
-- a1: Data round-trip (Lua version)
--
-- Lua literal data survives a round-trip through a git blob.
-- Raw binary (all 256 byte values) also survives.
--

dofile((arg[0]:match("^(.*/)") or "") .. "common.lua")

local DIR = "/tmp/freechains/tests/a1_lua"
os.execute("rm -rf " .. DIR)
os.execute("mkdir -p " .. DIR)
os.execute("git init --bare " .. DIR .. "/repo.git -q")

local GIT = "GIT_DIR=" .. DIR .. "/repo.git git"

-- --- Test 1: Lua literal table round-trip through git blob ---

local LUA_DATA = [[return {
    name  = "test",
    value = 42,
    tags  = {"alpha", "beta", "gamma"},
    nested = {
        x = 1.5,
        y = true,
        z = "hello world",
    },
}]]

local tmp = tmpwrite(LUA_DATA)
local HASH = shell("cat " .. tmp .. " | " .. GIT .. " hash-object -w --stdin")
os.remove(tmp)
local READBACK = shell(GIT .. " cat-file blob " .. HASH)

assert_eq(LUA_DATA, READBACK, "lua literal round-trip")

-- --- Test 2: Same content produces same hash (content-addressing) ---

local tmp2 = tmpwrite(LUA_DATA)
local HASH2 = shell("cat " .. tmp2 .. " | " .. GIT .. " hash-object -w --stdin")
os.remove(tmp2)
assert_eq(HASH, HASH2, "same content = same hash")

-- --- Test 3: Different content produces different hash ---

local tmp3 = tmpwrite("different data")
local HASH3 = shell("cat " .. tmp3 .. " | " .. GIT .. " hash-object -w --stdin")
os.remove(tmp3)
assert_neq(HASH, HASH3, "different content = different hash")

-- --- Test 4: All 256 byte values survive git blob round-trip ---

local bytes = {}
for i = 0, 255 do bytes[i+1] = string.char(i) end
local allbytes = table.concat(bytes)

writefile(DIR .. "/all_bytes.bin", allbytes)
local HASH4 = shell(GIT .. " hash-object -w -- " .. DIR .. "/all_bytes.bin")
os.execute(GIT .. " cat-file blob " .. HASH4 .. " > " .. DIR .. "/all_bytes_out.bin")
local readback_bytes = readfile(DIR .. "/all_bytes_out.bin")
assert_eq(allbytes, readback_bytes, "256 byte values round-trip")

-- --- Test 5: Empty payload ---

local tmp5 = tmpwrite("")
local HASH5 = shell("cat " .. tmp5 .. " | " .. GIT .. " hash-object -w --stdin")
os.remove(tmp5)
local READBACK5 = shell(GIT .. " cat-file blob " .. HASH5)
assert_eq("", READBACK5, "empty payload round-trip")

-- --- Test 6: Large payload (200KB) ---

local big = string.rep(".", 200000)
writefile(DIR .. "/big.bin", big)
local HASH6 = shell(GIT .. " hash-object -w -- " .. DIR .. "/big.bin")
os.execute(GIT .. " cat-file blob " .. HASH6 .. " > " .. DIR .. "/big_out.bin")
local readback_big = readfile(DIR .. "/big_out.bin")
assert_eq(big, readback_big, "200KB payload round-trip")

report()
