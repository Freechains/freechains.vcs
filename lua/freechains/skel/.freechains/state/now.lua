-- newest time among all ancestors of this commit (causal high-water).
-- A commit may sit at most `time.diff` below it: see `apply` in common.lua.
-- genesis has no real ancestor: `chains add` writes the chain creation time.
return 0   -- e.g. 1785000000
