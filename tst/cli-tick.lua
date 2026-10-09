#!/usr/bin/env lua5.4
require "tests"

-- The chain clock (plan 261008-tick): half ticks of
-- `half * max(0, 1 - 2r)`, r = reps of the members acting since the
-- tick start / all reps. A half tick refunds the posts charged since
-- the previous one (rule 2); every second close is a full tick that
-- rewards each member once for its first post since the previous
-- full tick (rule 1.b). The actor counts for the tick it closes; its
-- action lands in the next one.
-- Constants: cost 500, earn 1000, half 12h, cap 50K.

local H = 3600
local D = 24*H

local function REPS (exe, chain, now, pub)
    return exec {
        cmd = exe .. " --now=" .. now .. " chain " .. chain .. " reps member '" .. pub .. "'",
    }
end

local function POST (exe, chain, now, key, txt)
    return exec {
        cmd = exe .. " --now=" .. now .. " chain " .. chain .. " post inline '" .. txt .. "' --sign " .. key,
    }
end

-- QUIET CHAIN
do
    print("==> Quiet chain")

    -- GEN_4: 12500 each; KEY1 alone holds 25%, so its own activity
    -- shortens its tick to ~6.2h, never to 0
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /tick-quiet init " .. GEN_4,
    }

    do
        TEST "tick-quiet (refund at the half tick, reward at the full)"
        POST(ENV_EXE, "/tick-quiet", 0, KEY1, "p1")    -- 12000
        -- half tick closes at floor(12h * (1 - 2*12000/49500)) = 22254
        assert(REPS(ENV_EXE, "/tick-quiet", 20000, PUB1) == "12000", "pending: " .. REPS(ENV_EXE, "/tick-quiet", 20000, PUB1))
        assert(REPS(ENV_EXE, "/tick-quiet", 30000, PUB1) == "12500", "refund: " .. REPS(ENV_EXE, "/tick-quiet", 30000, PUB1))
        -- full tick 12h later (nobody acts): 22254 + 43200 = 65454
        assert(REPS(ENV_EXE, "/tick-quiet", 60000, PUB1) == "12500", "before full: " .. REPS(ENV_EXE, "/tick-quiet", 60000, PUB1))
        assert(REPS(ENV_EXE, "/tick-quiet", 70000, PUB1) == "13500", "reward: " .. REPS(ENV_EXE, "/tick-quiet", 70000, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /tick-quiet",
    }
end

-- ONE REWARD PER FULL TICK
do
    print("==> One reward per full tick")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /tick-one init " .. GEN_4,
    }

    do
        TEST "tick-one-reward (10 posts, one full tick, one reward)"
        for i = 1, 10 do
            POST(ENV_EXE, "/tick-one", 0, KEY1, "p" .. i)    -- 12500 -> 7500
        end
        -- KEY2 acts: KEY1 7500 + KEY2 12500 of 45000 = 44%, not yet
        POST(ENV_EXE, "/tick-one", 600, KEY2, "ack2")
        -- KEY3 acts: 72%: half tick closes at 601, the 10 posts refund
        POST(ENV_EXE, "/tick-one", 601, KEY3, "ack3")
        assert(REPS(ENV_EXE, "/tick-one", 602, PUB1) == "12500", "refund: " .. REPS(ENV_EXE, "/tick-one", 602, PUB1))
        -- a new tick: KEY2, KEY3 alone stay below 50% (their posts
        -- cost), KEY4 closes it: the full tick rewards KEY1 once
        POST(ENV_EXE, "/tick-one", 1200, KEY2, "ack2b")
        POST(ENV_EXE, "/tick-one", 1201, KEY3, "ack3b")
        POST(ENV_EXE, "/tick-one", 1202, KEY4, "ack4")
        assert(REPS(ENV_EXE, "/tick-one", 1203, PUB1) == "13500", "one reward: " .. REPS(ENV_EXE, "/tick-one", 1203, PUB1))
        -- p2..p10 never earn (today: one per day, 15500 at day 3)
        assert(REPS(ENV_EXE, "/tick-one", 3*D, PUB1) == "13500", "no more: " .. REPS(ENV_EXE, "/tick-one", 3*D, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /tick-one",
    }
end

-- MAJORITY
do
    print("==> Majority")

    -- GEN_2: 25000 each: either pioneer closes a half tick alone
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /tick-maj init " .. GEN_2,
    }

    do
        TEST "tick-majority (50% closes a half tick alone)"
        local P = POST(ENV_EXE, "/tick-maj", 0, KEY1, "p1")   -- closes #1; 24500
        -- KEY2's like closes #2 (full): refund +500, reward +1000,
        -- self-back +450
        exec {
            cmd = ENV_EXE .. " --now=10 chain /tick-maj like 1000 action " .. P .. " --sign " .. KEY2,
        }
        assert(REPS(ENV_EXE, "/tick-maj", 11, PUB1) == "26450", "liked: " .. REPS(ENV_EXE, "/tick-maj", 11, PUB1))
        assert(REPS(ENV_EXE, "/tick-maj", 11, PUB2) == "24000", "liker: " .. REPS(ENV_EXE, "/tick-maj", 11, PUB2))
        -- alone: p2 closes #3 (cost), p3 closes #4 (refund p2, reward
        -- p2, cost p3): 26450 - 500 + 500 + 1000 - 500 = 26950
        POST(ENV_EXE, "/tick-maj", 20, KEY1, "p2")
        POST(ENV_EXE, "/tick-maj", 30, KEY1, "p3")
        assert(REPS(ENV_EXE, "/tick-maj", 31, PUB1) == "26950", "alone: " .. REPS(ENV_EXE, "/tick-maj", 31, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /tick-maj",
    }
end

-- REORG: THE LOSER COLLAPSES INTO ONE TICK
do
    print("==> Reorg")

    local ROOT_A = ROOT .. "/cli-tick/A/"
    local ROOT_B = ROOT .. "/cli-tick/B/"
    local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
    local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
    local REPO_A = ROOT_A .. "/chains/tick/"
    local REPO_B = ROOT_B .. "/chains/tick/"
    exec { cmd = "mkdir -p " .. ROOT_A }
    exec { cmd = "mkdir -p " .. ROOT_B }

    -- GEN_3: KEY1, KEY2 at A (2/3 of the reps), KEY3 at B
    exec {
        cmd = EXE_A .. " --now=0 chains add /tick init " .. GEN_3,
    }
    exec {
        cmd = EXE_B .. " chains add /tick clone " .. REPO_A,
    }

    do
        TEST "tick-reorg-loser (a week alone pays once after the merge)"
        -- B alone: a post a day, each rewarded in B's own view
        POST(EXE_B, "/tick", 1*D, KEY3, "b1")
        POST(EXE_B, "/tick", 2*D, KEY3, "b2")
        POST(EXE_B, "/tick", 3*D, KEY3, "b3")
        -- 16666 - 1500 + 1000 (b1, b2 refunded) + 2000 (b1, b2 rewarded)
        assert(REPS(EXE_B, "/tick", 3*D+1, PUB3) == "18166", "B alone: " .. REPS(EXE_B, "/tick", 3*D+1, PUB3))

        -- A acts later than B's dates, then merges B: A wins (KEY1
        -- and KEY2 act on A's side, so its exclusive members outweigh
        -- KEY3), B's posts are appended at A's chain time, in one tick
        POST(EXE_A, "/tick", 4*D, KEY1, "a1")
        POST(EXE_A, "/tick", 4*D+1, KEY2, "a2")   -- closes a half tick
        exec {
            cmd = EXE_A .. " --now=" .. (4*D+10) .. " chain /tick sync recv " .. REPO_B,
        }
        -- 16666 - 1500 + 1500 (refunds) + 1000 (one reward for b1)
        assert(REPS(EXE_A, "/tick", 5*D, PUB3) == "17666", "A's view: " .. REPS(EXE_A, "/tick", 5*D, PUB3))

        -- B adopts A's order and converges
        exec {
            cmd = EXE_B .. " --now=" .. (5*D+10) .. " chain /tick sync recv " .. REPO_A,
        }
        assert(REPS(EXE_B, "/tick", 6*D, PUB3) == REPS(EXE_A, "/tick", 6*D, PUB3), "converge: " .. REPS(EXE_B, "/tick", 6*D, PUB3) .. " vs " .. REPS(EXE_A, "/tick", 6*D, PUB3))
        assert(REPS(EXE_B, "/tick", 6*D, PUB3) == "17666", "B's view: " .. REPS(EXE_B, "/tick", 6*D, PUB3))
    end
end

print("<== ALL PASSED")
