#!/usr/bin/env lua5.4
require "tests"

-- Reward slot (rule 1.b), plan 261008-adaptive-settle:
--  (a) depth-1 queue: a settled post is credited if the slot is
--      open, parked if nothing is parked, else dropped (no credit);
--      `last` = reward time (no grid catch-up)
--  (b) slot in activity time: the slot reopens
--      `full * max(0, 1 - 2r)` after the last reward, with r = reps
--      of OTHER members acting after that reward / reps of all
--      other members; the post itself settles by the same formula
--      anchored at the post (same ratio as the quarantine)
-- Constants: cost 500, earn 1000, half 12h, full 24h, cap 50K.

local H = 3600
local D = 24*H

local function REPS (chain, now, pub)
    return exec {
        cmd = ENV_EXE .. " --now=" .. now .. " chain " .. chain .. " reps member '" .. pub .. "'",
    }
end

local function POST (chain, now, key, txt)
    return exec {
        cmd = ENV_EXE .. " --now=" .. now .. " chain " .. chain .. " post inline '" .. txt .. "' --sign " .. key,
    }
end

-- (a) DEPTH-1 QUEUE
do
    print("==> Depth-1 queue")

    -- GEN_2: KEY1 = 25000, below the cap; KEY2 never acts, so
    -- r = 0 and every wait is the 24h ceiling
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /slot-queue init " .. GEN_2,
    }

    do
        TEST "slot-depth-1 (3 posts in a day pay 2 over 2 days)"
        POST("/slot-queue", 0, KEY1, "p1")   -- 24500
        POST("/slot-queue", 0, KEY1, "p2")   -- refund p1, cost p2
        POST("/slot-queue", 0, KEY1, "p3")   -- refund p2, cost p3
        -- day 1: refund p3, p1 credited, p2 parked, p3 dropped
        assert(REPS("/slot-queue", 1*D, PUB1) == "26000", "day 1: " .. REPS("/slot-queue", 1*D, PUB1))
        -- day 2: p2 credited
        assert(REPS("/slot-queue", 2*D, PUB1) == "27000", "day 2: " .. REPS("/slot-queue", 2*D, PUB1))
        -- day 3: nothing left (today: p3 +1000 -> 28000)
        assert(REPS("/slot-queue", 3*D, PUB1) == "27000", "day 3: " .. REPS("/slot-queue", 3*D, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /slot-queue",
    }

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /slot-gap init " .. GEN_2,
    }

    do
        TEST "slot-no-catchup (idle gap does not bank slots)"
        POST("/slot-gap", 0, KEY1, "p1")
        -- p1 settles and is credited at 1D: last = 1D
        assert(REPS("/slot-gap", 1*D, PUB1) == "26000", "day 1: " .. REPS("/slot-gap", 1*D, PUB1))
        -- idle until day 5, then two posts
        POST("/slot-gap", 5*D, KEY1, "p2")   -- 25500
        POST("/slot-gap", 5*D, KEY1, "p3")   -- refund p2, cost p3
        -- day 6: refund p3; p2 and p3 settle; slot open since 2D:
        -- p2 credited, p3 parked (today: grid pays both -> 28000)
        assert(REPS("/slot-gap", 6*D, PUB1) == "27000", "day 6: " .. REPS("/slot-gap", 6*D, PUB1))
        -- day 7: p3 credited
        assert(REPS("/slot-gap", 7*D, PUB1) == "28000", "day 7: " .. REPS("/slot-gap", 7*D, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /slot-gap",
    }
end

-- (b) SLOT IN ACTIVITY TIME
do
    print("==> Slot anchor")

    -- GEN_4: 12500 each. KEY1 alone holds 25%: its own posts do not
    -- refund nor settle by themselves (wait 6h / 12h).
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /slot-anchor init " .. GEN_4,
    }

    do
        TEST "slot-anchor-one-reward (10 posts, one ack, one reward)"
        for i = 1, 10 do
            POST("/slot-anchor", 0, KEY1, "p" .. i)     -- 12500 -> 7500
        end
        -- KEY2 acts at 10min: 25% after the posts, not enough
        POST("/slot-anchor", 600, KEY2, "ack2")
        -- KEY3 acts: KEY2 + KEY3 >= 50% of all reps: the 10 posts
        -- refund (+5000) and settle at 601; p1 credited (slot open),
        -- p2 parked, p3..p10 dropped (today: nothing before 24h)
        POST("/slot-anchor", 601, KEY3, "ack3")
        assert(REPS("/slot-anchor", 602, PUB1) == "13500", "after ack: " .. REPS("/slot-anchor", 602, PUB1))
    end

    do
        TEST "slot-anchor-second-ack (fresh ack after the reward reopens)"
        -- KEY2 alone after the reward: 1/3 of the others, slot closed
        POST("/slot-anchor", 1200, KEY2, "ack2b")
        assert(REPS("/slot-anchor", 1201, PUB1) == "13500", "one acker: " .. REPS("/slot-anchor", 1201, PUB1))
        -- KEY3 too: 2/3 of the others acted after the reward: p2 credited
        POST("/slot-anchor", 1201, KEY3, "ack3b")
        assert(REPS("/slot-anchor", 1202, PUB1) == "14500", "two ackers: " .. REPS("/slot-anchor", 1202, PUB1))
        -- p3..p10 were dropped: no further credit ever
        -- (today: p1 at 1D, p2 at 2D, p3 at 3D -> 15500)
        assert(REPS("/slot-anchor", 3*D, PUB1) == "14500", "day 3: " .. REPS("/slot-anchor", 3*D, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /slot-anchor",
    }
end

-- (b) SELF EXCLUDED
do
    print("==> Self excluded")

    -- GEN_4, then KEY2..KEY4 like KEY1 10000 each (9000 after tax):
    -- KEY1 = 39500 (79%), others 2500 each
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /slot-self init " .. GEN_4,
    }
    for _, k in ipairs { KEY2, KEY3, KEY4 } do
        exec {
            cmd = ENV_EXE .. " --now=0 chain /slot-self like 10000 member '" .. PUB1 .. "' --sign " .. k,
        }
    end

    do
        TEST "slot-self-excluded (majority acting alone keeps 24h)"
        assert(REPS("/slot-self", 50, PUB1) == "39500", "setup: " .. REPS("/slot-self", 50, PUB1))
        POST("/slot-self", 100, KEY1, "p1")   -- 39000
        POST("/slot-self", 100, KEY1, "p2")   -- refund p1 (self >= 50%), cost p2
        -- p3: refund p2, p1 settles (own ratio >= 50%) and is credited
        -- (slot open), cost p3 -> 40000 (today: 39000, no 24h yet)
        POST("/slot-self", 200, KEY1, "p3")
        -- p4: refund p3; p3 settles, slot closed: p2 parked, p3 dropped
        POST("/slot-self", 300, KEY1, "p4")
        assert(REPS("/slot-self", 400, PUB1) == "40000", "own ack: " .. REPS("/slot-self", 400, PUB1))
        -- nobody else acted after the reward at 200: the slot keeps
        -- the 24h ceiling even though KEY1 holds 79% and keeps acting
        -- (self counted: p2 credited at 300 -> 41000)
        assert(REPS("/slot-self", 200+D-100, PUB1) == "40000", "before ceiling: " .. REPS("/slot-self", 200+D-100, PUB1))
        assert(REPS("/slot-self", 200+D+100, PUB1) == "41000", "after ceiling: " .. REPS("/slot-self", 200+D+100, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /slot-self",
    }
end

-- (b) ACCELERATION
do
    print("==> Acceleration")

    -- GEN_4, all four post every round (1000s apart): each round the
    -- others hold >= 50% of the rest, so KEY1 is credited once per
    -- round, never waiting 24h
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /slot-fast init " .. GEN_4,
    }

    do
        TEST "slot-acceleration (one reward per round of activity)"
        for k = 0, 3 do
            local t = 1000*k
            POST("/slot-fast", t+0, KEY1, "a" .. k)
            POST("/slot-fast", t+1, KEY2, "b" .. k)
            POST("/slot-fast", t+2, KEY3, "c" .. k)
            POST("/slot-fast", t+3, KEY4, "d" .. k)
        end
        -- 4 rounds: a0..a3 all refunded, settled, and credited
        -- (today: 12500, first credit at 1D)
        assert(REPS("/slot-fast", 3004, PUB1) == "16500", "4 rounds: " .. REPS("/slot-fast", 3004, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /slot-fast",
    }
end

print("<== ALL PASSED")
