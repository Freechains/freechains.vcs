# `chains add init`: unrestricted chains, then `--dictator`

- Step 1: no `--pioneer` and no `--dictator` => unrestricted chain
- Step 2: `--dictator=<key>`: an author that is never gated
- Same mechanism: gate skipped; ALL economics still apply

# Before step 1

- no pioneers => nobody held reps => nobody could post
- `--beg` needed a liker with reps => dead chain by design
- `chains.md` claimed "fully open" but the gates said otherwise

# Step 1: unrestricted chain  [x] DONE

- `chains.lua`: `open = (#pios == 0)` in the genesis `G`
- `rules.lua`: `ungated(G)` skips the post and the vote gates
- `rules.lua`: the vote debit now guards a missing author entry
  (a fresh key could not vote before, so it never showed)
- `tst/cli-open.lua` + `cli-chains.lua` asserts; suite 42/42
- deviation: `ungated(G)`, not `ungated(G, key)` -- no key is
  read until `--dictator` exists

- genesis with zero pioneers and zero dictators => `open`
    - derived from the genesis, so consensual and immutable
    - no new genesis line, no flag in local config
- what "unrestricted" means: the two gates are skipped
    - post: `insufficient reputation` (`rules.lua:229`)
    - vote: `insufficient reputation` (`rules.lua:291`)
    - `--beg` is now REFUSED: an open chain admits everyone,
      so there is nothing to be admitted into
- what still applies (the economics):
    - post costs `C.reps.cost`, refunds at 12h, consolidates 24h
    - votes debit `n`, tax, split to target/author
    - daily `earn`, `cap` at `C.reps.max`
    - consensus still orders branches by author reps
- an UNSIGNED post lands directly, charged to the shared
  `anonymous` account: DONE, `done/260829-anon.md`
- consequence: balances may go NEGATIVE (debt)
    - reps become a score, not a permission
    - `reps author` prints the negative number as is
    - consensus: a side in debt loses to a side at zero

# Step 2: `--dictator`  [x] DONE

```
freechains chains add <alias> init [--pioneer=<key>]... [--dictator=<key>]...
```

- repeats, resolves keys exactly like `--pioneer`
- genesis SECTION per role: `dictators:` then `pioneers:`
- `G.authors[key].dictator = true`, `reps = 0` unless a pioneer
- dictators do NOT enter the `reps.max // #pioneers` split
    - so no cap on how many: they split nothing
- gate predicate, one place:
    - `ungated(G, key) = G.open or G.authors[key].dictator`
    - named `dictator`, not `god`: it matches the flag and the
      genesis, and `ungated` would name only one of its effects
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

- `genesis()`: parse the sections, set `A[key].dictator = true`
- set `G.open = (#pios == 0 and #dics == 0)`
- `init`: emit both headers, each section sorted
- a key that is both: ALLOWED, it takes the split and the mark

## `src/freechains/chain/rules.lua`

- `local function ungated (G, key)`
- post gate: `if not ungated and reps < cost`
- vote gate: `if not self_revoke and not ungated and reps < |n|`
- everything else untouched (debits, refund, earn, cap, advance)

## `src/freechains/chain/consensus.lua`

- step 1: unchanged (negative sums compare fine)
- step 2: DECIDED: a side with a dictator wins outright
    - exactly one side has one => that side wins
    - both or neither => normal criteria (reps sum, then the rest)
    - check before the reps sum, as a boolean, no `inf` arithmetic

## `src/freechains/chain/reps.lua`

- unchanged for step 1

# Tests

- 4 test files use `GEN_0`; none asserts `insufficient reputation`
  under it, so step 1 breaks no existing expectation
- [x] `cli-open.lua`: `GEN_0` chain, unknown key posts, balance
  goes to `-500`, refunds to `0` at 12h, vote from debt allowed
    - also: a pioneered chain still refuses (regression guard)
    - not covered: a debt branch losing consensus (needs a
      two-peer harness; the comparison is plain arithmetic)

# Consequences

- step 1: a chain anyone can use, spam-resistant only by ordering
  (debt sinks a branch in consensus), not by admission
- step 2: a dictator can admit anyone (`like <n> author`) and
  revoke anything, forever; the chain has an owner by construction
- Sybil-resistance unchanged where gates exist

# Genesis format

- v0.21 replaced the bare/marked lines with two sections
- both headers ALWAYS present: an open chain states it
- fixed order, sorted keys, strict lines (no blank line)
- DECIDED: no back compatibility with a v0.20 genesis
- DECIDED: a key repeated in a section is NOT rejected
- `genesis.md` rewritten: the old spec predated all of this

# Open

- hard fork: a dictator branch is still refused by entrenchment
- `chains.md` "fully open" text: now true, keep

# Won't do

- no `--dictator` on `clone`: it comes with the genesis
- no runtime promotion or demotion
- no partial dictator (e.g. revoke-only)
- no `inf` display: balances are real numbers now
