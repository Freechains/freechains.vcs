# 260819-blacklist

- durable local rejection of a received malicious branch
- born from 260819-abandon.md "key fact": received history
  resurrects on next recv; abandon is not durable
- target case: prefabricated sibling branch that passes
  fetch validation and does not affect my order
- phases: discuss -> settle -> implement

# Phase 1: discuss

## Why abandon is not enough

- abandon rewinds locally; next recv restores the branch
- dislike/revoke suppress reps but keep the actions
- nothing lets a peer refuse specific content for good

## Mechanism sketch

- `abandon --ban <aid>`: rewind + record a ban ref
    - ref: `refs/blacklist/<aid>`
- recv: after fetch, before merge, scan `HEAD..FETCH_HEAD`
    - if any banned aid appears: refuse the sync
    - error: `chain recv : banned action`
- `list blacklist`: show active bans (must be visible)
- unban: delete the ref (name? `chain unban <aid>`?)

## Keying: aid vs author

- aid-keyed: exact, cheap, but brittle
    - re-minted branch = new timestamps = new aids
    - ban walks right past it
- author-keyed: `refs/blacklist/key-<pub>`
    - refuse syncs introducing actions signed by the key
    - stronger; aligns with reps
    - still weak vs fresh self-farmed keys
- lean: support both; aid for surgical, author for durable

## Hard-fork caveat

- a ban is a standing hard fork by choice
- refuses EVERY peer carrying the banned content
- fine while branch is marginal (only attacker serves it)
- self-partition if the community merges it
- must be explicit and listable, never silent

## Upstream question

- how did the branch pass fetch validation with reps?
- self-farmed reps inside own branch = the real hole
- pioneer rules on received branches may refuse it there
- then blacklist is a manual fallback, not the defense
- may belong in threats.md as its own entry

## Open points

- ban before ever receiving? (preemptive, by hash/key)
- interaction with abandon crossing rule (linear suffix)
- does a ban survive prune? (refs vs flattened history)
- send: do I advertise bans? (no: local policy only)

# Phase 2: settle

- pending

# Phase 3: implement

- pending
