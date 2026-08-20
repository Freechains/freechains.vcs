# `chains add init --dictator`

- Keys that never run out of reps, listed at genesis
- Same shape as `--pioneer`, see 260820-init-pioneer.md
- Possible: yes, as a FLAG per author, never as a number

# Goal

```
freechains chains add <alias> init [--pioneer=<key>]... [--dictator=<key>]...
```

- `--dictator` repeats, resolves keys exactly like `--pioneer`
- A dictator never spends, never mints, never caps
- A dictator may also be a pioneer, or hold no reps at all

# Why a flag, not infinite reps

- `serial()` writes numbers raw, so `inf` lands in the state
    - `load` reads `inf` as a nil global: state file breaks
- `advance()` sums `cur`/`tot` over reps: `inf/inf` is nan
- `cap()` would clamp it back to `reps.max` on every step
- So: `G.authors[k].god = true`, booleans already serialize

# Where stored

- Genesis, next to `pioneers`, never in local config
- Must be consensual: every peer replays the same rules
- Immutable: no way to add or drop a dictator later
    - a chain that wants one must be created with it

# What changes

## `src/freechains/chains.lua`

- `pioneers()` also reads `T.dictators`
- Marks `A[key].god = true`, with `reps = 0` if not a pioneer
- Dictators do NOT enter the `reps.max // #pioneers` split

## `src/freechains/chain/rules.lua`

- Gates: skip `insufficient reputation` when `god` (post, vote)
- Debits: skip both subtractions when `god`
    - post `- C.reps.cost`, vote `- math.abs(act.n)`
- `cap()`: skip gods
- `advance()`: exclude gods from `cur` AND `tot`
    - else one god makes `ratio` ~1 and every post refunds at once
- Consolidation: skip the `earn` grant for gods

## `src/freechains/chain/consensus.lua`

- `reps(keys)` sums the side's authors
- A god side must win: count each god as `C.reps.max`
    - keeps the sum an integer, no `inf` in the compare
- Two god sides tie and fall through to the next criterion

## `src/freechains/chain/reps.lua`

- `reps author <pub>`: print `inf` for a god
- `reps authors`: gods sort first, printed as `inf`
- `reps action`/`actions` unchanged: actions hold real numbers

# Display

- DECIDED: `inf`, not `god` or `*`
    - it is the arithmetic truth, and reads as "no limit"
    - `god` is the internal name, not the user's word
- A vote by a god still shows its own `n` on the target
    - only the caster's balance is unbounded

# Consequences

- A dictator can admit anyone: unlimited `like <n> author`
- A dictator can revoke anything: `revoke` still needs `n`,
  but never runs out
- A dictator's branch always wins consensus ordering
- A dictator cannot be dislodged: no way to revoke a key
- Sybil-resistance is intact: extra keys are still worth zero
- Permissionless is NOT: the chain has an owner by construction

# Open

- Does a god break rule 1 (hard fork)?
    - its branch always wins, but entrenchment refuses first
    - so a god can still be locked out by a settled peer
- Should `reps authors` list gods at all, or only real balances?
- Cap on the number of dictators, as `too many pioneers` does?

# Won't do

- No `--dictator` on `clone`: it comes with the genesis
- No runtime promotion or demotion of a dictator
- No partial dictator (e.g. revoke-only): one flag, all powers
