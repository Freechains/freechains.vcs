local s   = 1
local min = 60 * s
local h   = 60 * min

local unit = 1000

return {
    time = {
        diff    = 1*h,          -- max post time diff tolerance (clock drift)
        half    = 12*h,         -- halfway post discount period
        full    = 24*h,         -- fullway post consolidation period
        --hardfork = 7*24*h,    -- branch divergence limit
    },
    reps = {
        unit    = 1*unit,       -- 1 ext rep = 1000 internal
        --pioneer = 30*unit,    -- 30 ext split among pioneers
        cost    = 1*unit,       -- 1 ext per signed post
        max     = 30*unit,      -- 30 ext cap per author
    },
    like = {
        tax     = 10,           -- 10% burned on likes
        split   = 2,            -- 50/50 split (divisor)
    },
    --dislike = {
    --    min = 3,              -- min dislikes for revocation
    --},
    --post = {
    --    size = 131072,        -- 128 KB max payload
    --},
}
