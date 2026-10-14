#!/usr/bin/env lua5.4

-- Same actions, same order, whatever the sync path.
--
-- Peers post and vote concurrently, then pull from each other in a
-- random order (seeded: reproducible). Once every peer holds every
-- action (full gossip), all must agree on the main commit and on
-- the order: a sync joins the tip SET in one canonical merge, so
-- the merge structure carries no trace of who met whom first.
-- Short chain time: nothing settles, no hard fork applies.

require "tests"

local DIR  = ROOT .. "/merge-paths/"
local KEYS = { KEY1, KEY2, KEY3 }
local NP   = 4      -- peers
local SEEDS = { 1, 2, 3, 4, 5, 6, 7, 8 }

for _, seed in ipairs(SEEDS) do
    print("==> Seed " .. seed)
    math.randomseed(seed)

    local alias = "/mp" .. seed
    local P = {}
    for i = 1, NP do
        local root = DIR .. seed .. "/" .. i .. "/"
        exec {
            cmd = "mkdir -p " .. root,
        }
        P[i] = {
            exe  = ENV .. " ../src/freechains.lua --root " .. root,
            repo = root .. "chains" .. alias .. "/",
        }
    end

    -- GEN_3 + likes: K1 > K2 > K3, but K2 + K3 > K1 (pairwise
    -- merges ordered the same posts apart, tst/hardfork-merges.lua)
    TEST "peer 1 creates the chain; K2 and K3 like the seed"
    exec {
        cmd = P[1].exe .. " --now=1000 chains add " .. alias .. " init " .. GEN_3,
    }
    local seed_ = exec {
        cmd = P[1].exe .. " --now=1100 chain " .. alias .. " post inline 'seed' --sign " .. KEY1,
    }
    exec {
        cmd = P[1].exe .. " --now=1200 chain " .. alias .. " like 1000 action " .. seed_ .. " --sign " .. KEY2,
    }
    exec {
        cmd = P[1].exe .. " --now=1300 chain " .. alias .. " like 2000 action " .. seed_ .. " --sign " .. KEY3,
    }
    for i = 2, NP do
        exec {
            cmd = P[i].exe .. " chains add " .. alias .. " clone " .. P[1].repo,
        }
    end

    -- rounds: each peer may post or like, then random pulls
    local now = 2000
    local posts = { seed_ }
    for round = 1, 3 do
        TEST("round " .. round .. ": concurrent actions, random pulls")
        for i = 1, NP do
            now = now + 10
            local key = KEYS[math.random(#KEYS)]
            if (#posts > 0) and (math.random() < 0.3) then
                local tgt = posts[math.random(#posts)]
                exec { err=false, stderr=false,
                    cmd = P[i].exe .. " --now=" .. now .. " chain " .. alias .. " like 500 action " .. tgt .. " --sign " .. key,
                }
            else
                local cid = exec { err=false, stderr=false,
                    cmd = P[i].exe .. " --now=" .. now .. " chain " .. alias .. " post inline 'p" .. round .. i .. "' --sign " .. key,
                }
                if cid then
                    posts[#posts+1] = cid
                end
            end
        end
        for _ = 1, NP do
            local a, b = math.random(NP), math.random(NP)
            if a ~= b then
                now = now + 10
                exec { stderr=false,
                    cmd = P[a].exe .. " --now=" .. now .. " chain " .. alias .. " sync recv " .. P[b].repo,
                }
            end
        end
    end

    -- full gossip: a ring in a random rotation, one hop per lap,
    -- so NP laps reach every peer
    TEST "full gossip"
    local off = math.random(NP)
    for _ = 1, NP do
        for k = 1, NP do
            local a = (k + off) % NP + 1
            local b = a % NP + 1
            now = now + 10
            exec { stderr=false,
                cmd = P[a].exe .. " --now=" .. now .. " chain " .. alias .. " sync recv " .. P[b].repo,
            }
        end
    end

    TEST "every peer: same actions, same main, same order"
    do
        local h1 = exec {
            cmd = "git -C " .. P[1].repo .. " rev-parse HEAD",
        }
        local O1, S1 = ORDER(P[1].exe, alias)
        local o1 = table.concat(O1, " ")
        for i = 2, NP do
            local h = exec {
                cmd = "git -C " .. P[i].repo .. " rev-parse HEAD",
            }
            local O, S = ORDER(P[i].exe, alias)
            assert(#O == #O1, "peer " .. i .. " holds " .. #O .. " actions, peer 1 " .. #O1)
            for k in pairs(S1) do
                assert(S[k], "peer " .. i .. " lacks " .. k)
            end
            assert(h == h1, "main of peer " .. i .. " differs")
            assert(table.concat(O, " ") == o1, "order of peer " .. i .. " differs")
        end
    end
end

print("<== ALL PASSED")
