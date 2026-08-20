
-- Reclaim what removal already unreferenced: a revoked payload
-- (`like` drops its `refs/payloads/` anchor) or an abandoned commit.
-- Local only: no signing, no network, no reps.
-- Never run against a concurrent writer: `post` writes the payload
-- blob before anchoring it, so it is briefly unreferenced.
-- Payloads live outside the tree, anchored only by `refs/payloads/`,
-- so dropping the anchor is enough for the bytes to go here.
-- The abandoned COMMITS survive in the HEAD reflog until it expires:
-- they carry action files (metadata), never content.

exec {
    cmd = "git -C " .. REPO .. " gc --prune=now --quiet",
    err = "chain sweep : git gc failed",
}
