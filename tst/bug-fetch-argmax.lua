#!/usr/bin/env lua5.4

-- A pull of MANY new posts must fetch their payloads.
--
-- `recv` fetches the payloads in one `git fetch`, one refspec per new
-- post, all on the command line: one `sh -c` string, which Linux caps
-- at 128 KB (MAX_ARG_STRLEN). About 1100 posts (115 bytes each) and
-- `io.popen` fails:
--  "attempt to index a nil value (local 'h')"
-- So a new peer cannot clone a chain past that, nor a peer pull that
-- many posts at once.
--
-- A: open chain, N posts (KEY1)
-- B: clones early, then recvs all N at once
-- C: clones at the end

require "tests"

local ROOT_A = ROOT .. "/bug-fetch-argmax/A/"
local ROOT_B = ROOT .. "/bug-fetch-argmax/B/"
local ROOT_C = ROOT .. "/bug-fetch-argmax/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local N  = 1200     -- past the cap (~1100)
local T0 = 1000

for _, r in ipairs { ROOT_A, ROOT_B, ROOT_C } do
    exec {
        cmd = "mkdir -p " .. r,
    }
end

do
    print("==> Test: fetch the payloads of " .. N .. " new posts")

    TEST "A creates open chain, B clones it"
    exec {
        cmd = EXE_A .. " --now=" .. T0 .. " chains add /bfa init",
    }
    exec {
        cmd = EXE_B .. " chains add /bfa clone " .. ROOT_A .. "/chains/bfa/",
    }

    TEST("A posts " .. N)
    local last
    for i = 1, N do
        last = exec {
            cmd = EXE_A .. " --now=" .. (T0 + i*60) .. " chain /bfa post inline 'p" .. i .. "' --sign " .. KEY1,
        }
    end

    TEST("B recvs A: " .. N .. " new posts at once")
    exec {
        cmd = EXE_B .. " --now=" .. (T0 + (N+1)*60) .. " chain /bfa sync recv " .. ROOT_A .. "/chains/bfa/",
    }

    TEST "C clones A"
    exec {
        cmd = EXE_C .. " chains add /bfa clone " .. ROOT_A .. "/chains/bfa/",
    }

    TEST "B and C read the last payload"
    for _, exe in ipairs { EXE_B, EXE_C } do
        local out = exec {
            cmd = exe .. " chain /bfa get payload " .. last,
        }
        assert(out == "p" .. N, "payload: " .. tostring(out))
    end
end

print("<== ALL PASSED")
