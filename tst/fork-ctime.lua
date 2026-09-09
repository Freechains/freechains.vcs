#!/usr/bin/env lua5.4
require "tests"

-- Settle by CONSENSUS TIME: a loser branch gets the chain time of its
-- merge, whatever its declared dates, so it stays loose for `time.fork`
-- at every peer that merged it, and the honest refutation (discard +
-- dislike) still propagates. Settling by declared timestamps froze such
-- a branch on arrival ("freeze-by-flood"); settling by count froze it
-- at 100 actions. Both are gone.
--
-- GEN_2: KEY1=25K, KEY2=25K. KEY2 likes seed with 10K so KEY1 > KEY2.
--
--                 seed[K1] -- like[K2]                (fork point)
--                            /        \
--   C (KEY2):         j1 .. jN                        old dates (1h apart)
--   A (KEY1):                          a1              3 weeks later
--   X (hub):   recv A, recv C  -> K1 wins: junk appended, ctime = 3w
--   A (KEY1):                          a1 -- dislike K2 (refutation)
--   X (hub):   recv A          -> K1 wins: junk voided, prefix intact
--
-- Test 2 repeats with 5 junk posts, but X's chain time advances 7 days
-- (a 6th junk post) before the refutation: the junk is settled by then
-- and the refutation is refused (hard fork), as a late winner should.

local HOUR = 3600
local WEEK = 7*24*HOUR
local T0   = 1000

local function ROOTS (name)
    local R = {}
    for _, p in ipairs { "A", "C", "X" } do
        local root = ROOT .. "/fork-ctime/" .. name .. "/" .. p .. "/"
        exec {
            cmd = "mkdir -p " .. root,
        }
        R[p] = {
            exe  = ENV .. " ../src/freechains.lua --root " .. root,
            repo = root .. "/chains/" .. name .. "/",
        }
    end
    return R
end

-- common prefix: A seeds, KEY2 likes, C and X clone, C farms `n` junk
-- posts with old dates, A posts a1 three weeks later, X merges both
local function SETUP (name, n)
    local R = ROOTS(name)
    local A, C, X = R.A, R.C, R.X

    TEST "A creates chain, seeds, KEY2 likes seed (KEY1 > KEY2)"
    exec {
        cmd = A.exe .. " --now=" .. T0 .. " chains add /" .. name .. " init " .. GEN_2,
    }
    local seed = exec {
        cmd = A.exe .. " --now=" .. (T0+100) .. " chain /" .. name .. " post inline 'seed\n' --sign " .. KEY1,
    }
    local like = exec {
        cmd = A.exe .. " --now=" .. (T0+200) .. " chain /" .. name .. " like 10000 action " .. seed .. " --sign " .. KEY2,
    }

    TEST "C and X clone"
    exec {
        cmd = C.exe .. " chains add /" .. name .. " clone " .. A.repo,
    }
    exec {
        cmd = X.exe .. " chains add /" .. name .. " clone " .. A.repo,
    }

    TEST("C farms " .. n .. " junk posts with KEY2, dated 1h apart")
    local J = {}
    for i = 1, n do
        J[i] = exec {
            cmd = C.exe .. " --now=" .. (T0+200+i*HOUR) .. " chain /" .. name .. " post inline 'j" .. i .. "\n' --sign " .. KEY2,
        }
    end

    TEST "A posts a1 three weeks later"
    local a1 = exec {
        cmd = A.exe .. " --now=" .. (T0+3*WEEK) .. " chain /" .. name .. " post inline 'a1\n' --sign " .. KEY1,
    }

    TEST "X recvs A (ff) and C (KEY1 wins: junk appended as loser)"
    exec {
        cmd = X.exe .. " --now=" .. (T0+3*WEEK+HOUR) .. " chain /" .. name .. " sync recv " .. A.repo,
    }
    exec {
        cmd = X.exe .. " --now=" .. (T0+3*WEEK+HOUR) .. " chain /" .. name .. " sync recv " .. C.repo,
    }
    do
        local O = ORDER(X.exe, "/" .. name)
        assert(#O == n+3, "expected " .. (n+3) .. " entries, got " .. #O)
        assert(O[1]==seed and O[2]==like and O[3]==a1, "prefix: seed, like, a1")
        for i = 1, n do
            assert(O[3+i] == J[i], "junk " .. i .. " out of order")
        end
    end

    TEST "A refutes: KEY1 dislikes KEY2 below the posting cost"
    local dis = exec {
        cmd = A.exe .. " --now=" .. (T0+3*WEEK+2*HOUR) .. " chain /" .. name .. " dislike 20000 member '" .. PUB2 .. "' --sign " .. KEY1,
    }

    return R, { seed=seed, like=like, a1=a1, dis=dis, J=J }
end

-- 1. fresh loser with old dates: loose at X, refutation propagates
do
    print("==> Test 1: old-dated loser stays loose; refutation propagates")

    local N = 100
    local R, H = SETUP("fc1", N)
    local X = R.X

    TEST "X recvs A's refutation: accepted (junk was loose, not settled)"
    exec {
        cmd = X.exe .. " --now=" .. (T0+3*WEEK+3*HOUR) .. " chain /fc1 sync recv " .. R.A.repo,
    }

    TEST "X: junk voided, prefix intact"
    do
        local O, S = ORDER(X.exe, "/fc1")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(O[1]==H.seed and O[2]==H.like and O[3]==H.a1 and O[4]==H.dis,
            "order: seed, like, a1, dislike")
        for i = 1, N do
            assert(not S[H.J[i]], "junk " .. i .. " should be voided")
        end
    end
end

-- 2. refutation after 7 days of consensus time: refused
do
    print("==> Test 2: junk settles after 7 days of chain time; refutation refused")

    local N = 5
    local R, H = SETUP("fc2", N)
    local C, X = R.C, R.X

    TEST "C posts j6 a week later; X recvs it (chain time +7d)"
    local j6 = exec {
        cmd = C.exe .. " --now=" .. (T0+4*WEEK) .. " chain /fc2 post inline 'j6\n' --sign " .. KEY2,
    }
    exec {
        cmd = X.exe .. " --now=" .. (T0+4*WEEK+HOUR) .. " chain /fc2 sync recv " .. C.repo,
    }

    TEST "X recvs A's refutation: hard fork (junk settled by chain time)"
    do
        -- the loser replay reports the voided junk before the verdict
        local err = FAIL {
            cmd = X.exe .. " --now=" .. (T0+4*WEEK+2*HOUR) .. " chain /fc2 sync recv " .. R.A.repo,
        }
        assert(err:find("ERROR : chain sync : hard fork\n", 1, true),
            "should fail with hard fork: " .. err)
    end

    TEST "X keeps its order untouched"
    do
        local O = ORDER(X.exe, "/fc2")
        assert(#O == N+4, "expected " .. (N+4) .. " entries, got " .. #O)
        assert(O[1]==H.seed and O[2]==H.like and O[3]==H.a1, "prefix: seed, like, a1")
        for i = 1, N do
            assert(O[3+i] == H.J[i], "junk " .. i .. " out of order")
        end
        assert(O[N+4] == j6, "j6 last")
    end
end

print("<== ALL PASSED")
