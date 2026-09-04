--[[
-- `chain <alias> sweep`
-- Reclaim unreferenced bytes and pack the state blobs.
-- Inputs:
--  - REPO [string]: the chain's bare repo dir
-- Outputs:
--  - none: the object db is packed, unanchored bytes are gone
-- Errors:
--  - "chain sweep : git gc failed"
-- Callers:
--  - dispatch (chain/init.lua): ARGS.sweep
--]]

-- Reclaim what removal already unreferenced, and PACK the state.
-- Local only: no signing, no network, no reps.
-- Never run against a concurrent writer: `post` writes the payload
-- blob before anchoring it, so it is briefly unreferenced.
--
-- Two kinds of bytes go here:
--  - revoked payloads (`like` drops the `refs/payloads/` anchor) and
--    discarded commits' payloads/state -- once unanchored, gc reaps
--  - per-action STATE blobs (`refs/states/*`): each is a full loose
--    blob until packed, so this gc DELTA-compresses the near-
--    identical versions into O(N). It is the reclaim step -- git's
--    auto-gc is incremental/skippable and leaves a loose tail, so
--    the explicit gc here is what reaches the packed floor.

exec {
    cmd = "git -C " .. REPO .. " gc --prune=now --quiet",
    err = "chain sweep : git gc failed",
}
