#!/usr/bin/env lua5.4

-- A pull must fetch the payloads of a chain with MANY revoked posts.
--
-- `recv` fetches every payload in one `git fetch`, with one negative
-- refspec per revoked post, all on the command line: one `sh -c`
-- string, which Linux caps at 128 KB (MAX_ARG_STRLEN). About 2260
-- revoked posts (58 bytes each) and `io.popen` fails:
--  "attempt to index a nil value (local 'h')"
--
-- A: open chain, N posts (KEY1), each self-revoked
-- B: clones early, then recvs all at once
-- C: clones at the end

require "tests"

local ROOT_A = ROOT .. "/bug-fetch-argmax/A/"
local ROOT_B = ROOT .. "/bug-fetch-argmax/B/"
local ROOT_C = ROOT .. "/bug-fetch-argmax/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local N  = 2400     -- past the cap (~2260)
local T0 = 1000

for _, r in ipairs { ROOT_A, ROOT_B, ROOT_C } do
    exec {
        cmd = "mkdir -p " .. r,
    }
end

do
    print("==> Test: fetch with " .. N .. " revoked posts")

    TEST "A creates open chain, B clones it"
    exec {
        cmd = EXE_A .. " --now=" .. T0 .. " chains add /bfa init",
    }
    exec {
        cmd = EXE_B .. " chains add /bfa clone " .. ROOT_A .. "/chains/bfa/",
    }

    TEST("A posts and self-revokes " .. N .. ", then posts 1")
    for i = 1, N do
        local t = T0 + i*60
        local cid = exec {
            cmd = EXE_A .. " --now=" .. t .. " chain /bfa post inline 'p" .. i .. "' --sign " .. KEY1,
        }
        exec {
            cmd = EXE_A .. " --now=" .. (t+1) .. " chain /bfa revoke 1000 " .. cid .. " --sign " .. KEY1,
        }
    end
    local last = exec {
        cmd = EXE_A .. " --now=" .. (T0 + (N+1)*60) .. " chain /bfa post inline 'last' --sign " .. KEY1,
    }

    TEST "B recvs A: all at once"
    exec {
        cmd = EXE_B .. " --now=" .. (T0 + (N+2)*60) .. " chain /bfa sync recv " .. ROOT_A .. "/chains/bfa/",
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
        assert(out == "last", "payload: " .. tostring(out))
    end
end

print("<== ALL PASSED")
