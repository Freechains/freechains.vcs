local s   = 1
local min = 60 * s
local h   = 60 * min

local unit = 1000

return {
    time = {
        diff    = 1*h,          -- max action time diff tolerance (clock drift)
        half    = 12*h,         -- halfway post discount period
        full    = 24*h,         -- fullway post consolidation period
    },
    fork = {
        time    = 7*24*h,       -- span of my settled order (hard fork)
        actions = 100,          -- entries of my settled order (hard fork)
    },
    reps = {
        --pioneer = 50*unit,    -- split among pioneers
        cost    = unit//2,      -- 500 per signed post (refunded at 12h)
        earn    = 1*unit,       -- 1000 minted per author per day
        revoke  = 1*unit,       -- 1000 minimum per revoke/unrevoke
        max     = 50*unit,      -- 50000 cap per author (100 posts)
    },
    vote = {
        tax     = 10,           -- 10% burned on votes
        split   = 2,            -- 50/50 split (divisor)
    },
    --post = {
    --    size = 131072,        -- 128 KB max payload
    --},
}
