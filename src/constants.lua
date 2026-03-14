local s   = 1
local min = 60 * s
local h   = 60 * min

return {
    -- timestamp validation
    TOLERANCE = 1*h,            -- max clock drift

    -- reputation scale
    SCALE = 1000,               -- 1 ext rep = 1000 internal

    -- reputation limits
    PIONEER_TOTAL = 30000,      -- 30 ext split among pioneers
    POST_COST     = 1000,       -- 1 ext per signed post
    MAX_REPS      = 30000,      -- 30 ext cap per author

    -- like transfer
    LIKE_TAX   = 10,            -- 10% burned on likes
    LIKE_SPLIT = 2,             -- 50/50 split (divisor)

    -- revocation
    DISLIKE_MIN = 3,            -- min dislikes for revocation

    -- post size
    POST_SIZE = 131072,         -- 128 KB max payload

    -- time windows
    DISCOUNT_MAX  = 12*h,       -- max discount period
    CONSOLIDATION = 24*h,       -- consolidation window
    HARD_FORK     = 7*24*h,     -- branch divergence limit
}
