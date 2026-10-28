#!/usr/bin/env lua5.4

-- A chain repo keeps a fixed, small set of refs (plan 261015-fetch-refs).
--
-- Snapshots and payloads live in two INDEX refs, each a tree keyed by
-- cid (`refs/<name>:a/b/c/d/<cid>`), not one ref per entry: every
-- fetch scans every local ref. A pull fetches payload blobs by id:
--  - protocol v2 serves any object, v0 needs
--    `uploadpack.allowReachableSHA1InWant` (blobs reachable from the
--    payloads index)
--  - one id the remote lacks fails the whole fetch: the batch splits,
--    the rest still arrives, the lacking one is left missing
--  - a later pull from a peer that holds it heals the gap

require "tests"

local ROOT_A = ROOT .. "/fetch-refs/A/"
local ROOT_B = ROOT .. "/fetch-refs/B/"
local ROOT_C = ROOT .. "/fetch-refs/C/"

-- B speaks protocol v0 (C the default, v2)
local V0 = "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.version GIT_CONFIG_VALUE_0=0"

local EXE_A = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B = ENV .. " " .. V0 .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local DIR_A = ROOT_A .. "/chains/fr/"
local DIR_B = ROOT_B .. "/chains/fr/"
local DIR_C = ROOT_C .. "/chains/fr/"

for _, r in ipairs { ROOT_A, ROOT_B, ROOT_C } do
    exec {
        cmd = "mkdir -p " .. r,
    }
end

--[[
-- The refs of a chain repo, sorted.
-- Inputs:
--  - dir [string]: the chain repo dir
-- Outputs:
--  - [string]: ref names, one per line (newline-terminated)
-- Errors:
--  - via exec: "bug found" if for-each-ref fails
-- Callers:
--  - main chunk (this file): the fixed ref set
--]]
local function refs (dir)
    return exec {
        cmd = "git -C " .. dir .. " for-each-ref --sort=refname --format='%(refname)'",
    }
end

--[[
-- Whether `dir`'s index `name` holds `cid`.
-- Inputs:
--  - dir  [string]: the chain repo dir
--  - name [string]: "local" | "payloads"
--  - cid  [string]: 40-hex commit hash
-- Outputs:
--  - [boolean]: the entry exists
-- Errors:
--  - none
-- Callers:
--  - main chunk (this file)
--]]
local function has (dir, name, cid)
    local _, code = exec { err=false, stderr=false,
        cmd = "git -C " .. dir .. " cat-file -e " .. IDX(name, cid),
    }
    return code == 0
end

--[[
-- The payload of `cid` as `dir`'s peer prints it.
-- Inputs:
--  - exe [string]: the peer's command prefix
--  - cid [string]: 40-hex commit hash
-- Outputs:
--  - [string|false]: the bytes, false when the blob is not here
-- Errors:
--  - none
-- Callers:
--  - main chunk (this file)
--]]
local function payload (exe, cid)
    return exec { err=false, stderr=false,
        cmd = exe .. " chain /fr get payload " .. cid,
    }
end

local GEN = exec {
    cmd = EXE_A .. " --now=1000 chains add /fr init " .. GEN_1,
}
local P = {}
for i = 1, 3 do
    P[i] = exec {
        cmd = EXE_A .. " --now=" .. (1000+i) .. " chain /fr post inline 'p" .. i .. "' --sign " .. KEY1,
    }
end

do
    print("==> Test: snapshots and payloads in two index refs")

    TEST "A holds the fixed ref set"
    local out = refs(DIR_A)
    assert(out == "refs/genesis\nrefs/heads/main\nrefs/local\nrefs/payloads\n", "refs: " .. out)

    TEST "every commit has a snapshot, every post a payload"
    assert(has(DIR_A, "local", GEN), "genesis snapshot")
    for i = 1, 3 do
        assert(has(DIR_A, "local", P[i]), "snapshot " .. i)
        assert(has(DIR_A, "payloads", P[i]), "payload " .. i)
    end
    assert(not has(DIR_A, "payloads", GEN), "genesis has no payload")

    TEST "the index trees are well formed"
    exec {
        cmd = "git -C " .. DIR_A .. " fsck --connectivity-only --no-dangling",
    }
    local n = exec {
        cmd = "git -C " .. DIR_A .. " ls-tree -r refs/payloads | wc -l",
    }
    assert(tonumber(n) == 3, "payload entries: " .. n)

    TEST "a sweep keeps both indexes"
    exec {
        cmd = EXE_A .. " chain /fr sweep",
    }
    for i = 1, 3 do
        assert(payload(EXE_A, P[i]) == "p" .. i, "payload after sweep " .. i)
    end
    assert(has(DIR_A, "local", P[3]), "snapshot after sweep")
end

do
    print("==> Test: payloads fetched by blob id")

    TEST "B clones A over protocol v0: every payload arrives"
    exec {
        cmd = EXE_B .. " --now=1010 chains add /fr clone " .. DIR_A,
    }
    for i = 1, 3 do
        assert(payload(EXE_B, P[i]) == "p" .. i, "B payload " .. i)
        assert(has(DIR_B, "payloads", P[i]), "B payload entry " .. i)
    end
    local out = refs(DIR_B)
    assert(out == "refs/genesis\nrefs/heads/main\nrefs/local\nrefs/payloads\n", "B refs: " .. out)
end

do
    print("==> Test: a blob the remote lacks")

    -- A loses p2's bytes, the way a removal would
    IDX_DEL(DIR_A, "payloads", P[2])
    exec {
        cmd = "git -C " .. DIR_A .. " gc --prune=now --quiet",
    }

    TEST "C clones A: the others arrive, p2 is missing"
    exec {
        cmd = EXE_C .. " --now=1010 chains add /fr clone " .. DIR_A,
    }
    assert(payload(EXE_C, P[1]) == "p1", "C payload 1")
    assert(payload(EXE_C, P[3]) == "p3", "C payload 3")
    assert(not has(DIR_C, "payloads", P[2]), "C has no p2 entry")
    local f = assert(io.open(DIR_C .. "payloads-missing"))
    local miss = f:read("a")
    f:close()
    assert(miss == P[2] .. "\n", "missing: " .. miss)

    TEST "C pulls from B: p2 heals"
    exec {
        cmd = EXE_C .. " --now=1020 chain /fr sync recv " .. DIR_B,
    }
    assert(payload(EXE_C, P[2]) == "p2", "C payload 2")
    assert(has(DIR_C, "payloads", P[2]), "C p2 entry")
    local f = assert(io.open(DIR_C .. "payloads-missing"))
    local miss = f:read("a")
    f:close()
    assert(miss == "", "missing: " .. miss)
end

print("<== ALL PASSED")
