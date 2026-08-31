# Minimum vote

- `like 1` passes today: only non-zero integer + gate
- flood: an author at cap mints 50k commits (1 rep each);
  `earn` sustains 1000 commits/day -- every peer pays a
  snapshot + advance per commit
- dust is also tax-free: `n*90//100 = 0` for n < 10, so
  nothing reaches the target and no tax is rounded
- posts cost 500: dust likes are 500x cheaper per commit
  than the designed spam price

# Decision  [x] DONE

- floor ALL votes at `C.reps.cost` (500)
- story: every chain action costs at least a post
    - post 500, vote >= 500, revoke >= 1000
- flood collapses to the post rate (2/day sustained)
- `like 500` keeps working: beg admission floors there,
  and tests use it
- closes the tax hole: n >= 500 => tax >= 50

# Revoke stays 1000

- `is_revoked`: ANY net negative sum hides the post -- there
  is no -1000 threshold, the floor is the only price
- so 1000 = one earn day = 2 posts: burying someone else's
  content costs MORE than speech, on purpose
- unrevoke pays the same floor: the bidding war has an ante
- the 500 vote floor targets flood; the revoke floor targets
  censorship economics -- different purposes, both stand

# What changes

## `src/freechains/chain/rules.lua`

- one check beside the revoke floor, same error shape:
    - `invalid number : expects at least 500`
- the beg-like floor (`n < cost`) is now DEAD code: any
  n < 500 dies at the general floor first (cli-reps's
  dust-beg test now asserts the general error); fold it

# Not a vector

- free self-revoke: capped by `already revoked`, one per
  action; the reset (unrevoke) costs >= 1000
