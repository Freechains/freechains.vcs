#!/usr/bin/env lua
--
-- a4: Sorted set difference (Lua version)
--
-- Pure Lua implementation of sorted set difference.
-- Equivalent to `comm -23` on sorted files.
--

dofile((arg[0]:match("^(.*/)") or "") .. "common.lua")

--- Sorted set difference: elements in a not in b.
--- Both a and b must be sorted tables of strings.
function set_minus (a, b)
    local result = {}
    local bi = 1
    for _, v in ipairs(a) do
        while bi <= #b and b[bi] < v do
            bi = bi + 1
        end
        if bi > #b or b[bi] ~= v then
            result[#result+1] = v
        end
    end
    return result
end

--- Create a sorted set from arguments
function set_make (...)
    local t = {...}
    table.sort(t)
    return t
end

--- Format set as space-separated string
function set_str (t)
    return table.concat(t, " ")
end

-- --- Test 1: {1,2,5,10} - {3,5,7,10} = {1,2} ---

local s1 = set_make("1", "2", "5", "10")
local s2 = set_make("3", "5", "7", "10")
assert_eq("1 2", set_str(set_minus(s1, s2)), "s1 - s2")

-- --- Test 2: {3,5,7,10} - {1,2,5,10} = {3,7} ---

assert_eq("3 7", set_str(set_minus(s2, s1)), "s2 - s1")

-- --- Test 3: {4,5,7,8} - {3,5,7,10} = {4,8} ---

local s3 = set_make("4", "5", "7", "8")
local s4 = set_make("3", "5", "7", "10")
assert_eq("4 8", set_str(set_minus(s3, s4)), "s3 - s4")

-- --- Test 4: {3,5,7,10} - {4,5,7,8} = {10,3} (lexicographic: "10" < "3") ---

assert_eq("10 3", set_str(set_minus(s4, s3)), "s4 - s3")

-- --- Test 5: set minus itself = empty ---

assert_eq("", set_str(set_minus(s1, s1)), "s1 - s1 = empty")

-- --- Test 6: set minus empty = itself ---

assert_eq("1 10 2 5", set_str(set_minus(s1, {})), "s1 - empty = s1")

-- --- Test 7: empty minus set = empty ---

assert_eq("", set_str(set_minus({}, s1)), "empty - s1 = empty")

-- --- Test 8: with hash-like strings (simulating block hashes) ---

local local_set  = set_make("1_AAAA", "2_BBBB", "3_CCCC", "4_DDDD")
local remote_set = set_make("1_AAAA", "3_CCCC")
assert_eq("2_BBBB 4_DDDD", set_str(set_minus(local_set, remote_set)), "hash set difference")

report()
