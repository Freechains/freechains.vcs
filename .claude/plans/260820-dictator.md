# `chains add init`: unrestricted chains, then `--dictator`

- Step 1: no `--pioneer` and no `--dictator` => unrestricted chain
- Step 2: `--dictator=<key>`: an author that is never gated
- Same mechanism: gate skipped; ALL economics still apply

# Today

- no pioneers => nobody holds reps => nobody can post
- `--beg` needs a liker with reps => dead chain by construction
- `chains.md` claims "fully open" but the gates say otherwise

# Step 1: unrestricted chain

- genesis with zero pioneers and zero dictators => `open`
    - derived from the genesis, so consensual and immutable
    - no new genesis line, no flag in local config
- what "unrestricted" means: the two gates are skipped
    - post: `insufficient reputation` (`rules.lua:229`)
    - vote: `insufficient reputation` (`rules.lua:291`)
    - beg checks unchanged (`--beg` still means "parked")
- what still applies (the economics):
    - post costs `C.reps.cost`, refunds at 12h, consolidates 24h
    - votes debit `n`, tax, split to target/author
    - daily `earn`, `cap` at `C.reps.max`
    - consensus still orders branches by author reps
- consequence: balances may go NEGATIVE (debt)
    - reps become a score, not a permission
    - `reps author` prints the negative number as is
    - consensus: a side in debt loses to a side at zero

# Step 2: `--dictator`

```
freechains chains add <alias> init [--pioneer=<key>]... [--dictator=<key>]...
```

- repeats, resolves keys exactly like `--pioneer`
- genesis line per dictator, after pioneers (positional, marked)
- `G.authors[key].god = true`, `reps = 0` unless also a pioneer
- dictators do NOT enter the `reps.max // #pioneers` split
- gate predicate, one place:
    - `ungated(G, key) = G.open or (G.authors[key] and G.authors[key].god)`
- economics apply to a dictator too: it spends, mints, caps
    - it simply never hits the gate; its balance may go negative
    - DROPS the old "never spends, never mints" design
- `reps author <pub>`: real (possibly negative) number, plus a mark?
    - open: `inf` was decided before; now the number is meaningful

# Why derived `open`, not a flag

- a pioneer-less chain has no other sane meaning
- no way to forget it on clone: same genesis, same rules
- adding a pioneer or dictator later is impossible anyway

# What changes

## `src/freechains/chains.lua`

- `genesis()`: parse dictator lines, set `A[key].god = true`
- set `G.open = (#pios == 0 and #gods == 0)`
- `init`: emit dictator lines; reject a key that is both? (no: allow)

## `src/freechains/chain/rules.lua`

- `local function ungated (G, key)`
- post gate: `if not ungated and reps < cost`
- vote gate: `if not self_revoke and not ungated and reps < |n|`
- everything else untouched (debits, refund, earn, cap, advance)

## `src/freechains/chain/consensus.lua`

- step 1: unchanged (negative sums compare fine)
- step 2: DECIDED: a side with a god wins outright
    - exactly one side has a god => that side wins
    - both or neither => normal criteria (reps sum, then the rest)
    - check before the reps sum, as a boolean, no `inf` arithmetic

## `src/freechains/chain/reps.lua`

- unchanged for step 1

# Tests

- 4 test files use `GEN_0`; none asserts `insufficient reputation`
  under it, so step 1 breaks no existing expectation
- new: `cli-open.lua`: `GEN_0` chain, unknown key posts, balance
  goes to `-500`, refunds to `0` at 12h, vote from debt allowed

# Consequences

- step 1: a chain anyone can use, spam-resistant only by ordering
  (debt sinks a branch in consensus), not by admission
- step 2: a dictator can admit anyone (`like <n> author`) and
  revoke anything, forever; the chain has an owner by construction
- Sybil-resistance unchanged where gates exist

# Open

- hard fork: a god branch is still refused by entrenchment
- cap on number of dictators, as `too many pioneers`?
- `chains.md` "fully open" text: now true, keep

# Won't do

- no `--dictator` on `clone`: it comes with the genesis
- no runtime promotion or demotion
- no partial dictator (e.g. revoke-only)
- no `inf` display: balances are real numbers now
