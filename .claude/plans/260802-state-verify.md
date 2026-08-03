# State Verification: context-free, on receive

Supersedes [state-hash.md](state-hash.md), which shipped the
fast-forward comparison and recorded the rest as out of scope:
*"send hook, reset/rewrite, non-FF all dropped from scope"*.
This closes the non-FF case, and does it without the traversal
coupling that the branch `260802-bug-forged-state` currently has.

## 1. The bug

`.freechains/state/` does two jobs: it RECORDS what the state was,
and it ANCHORS a future replay. Only the first was ever checked,
and only on one path.

`commit()` in sync.lua validates a `state` commit with exactly one
test (sync.lua:351):

```lua
assert(kind == 'state')
-- need to check now, since it is derived, not trusted
local mx = PEAKS(parents(hash))
if PEAK(hash) ~= mx then error("invalid state : now", 0) end
```

`now` only. `authors.lua`, `posts.lua` and `order.lua` are never
compared, and the mode check permits `A|M` on all four paths, so a
commit that rewrites reputation is well-formed by every rule that
exists. The comment is right about `now` being derived, not
trusted -- that reasoning was simply never extended.

The full comparison exists only after a fast-forward
(sync.lua:485-493): `write(G_rem)` then
`git diff --quiet HEAD -- .freechains/state/`.

### Why "the values are ignored" is not safety

On the diverge path the forged values ARE ignored -- `G_rem` is
rebuilt by replay, `G_fst` recomputed, a fresh state commit
written. `tst/bug-forged-state.lua` confirms it: after the sync
the victim's `authors.lua` correctly reads 14000, not the forged
30000.

But the commit is still **accepted into history**. What was
ignored as a record survives as an anchor, and later this runs
with no validation at all (sync.lua:391):

```lua
G_oct = {
    authors = F(".freechains/state/authors.lua"),   -- F reads `oct`
    ...
}
```

Those numbers then become the basis for replay AND the input to
`consensus()`, which sums `G.authors[key].reps` to decide **which
branch wins a merge**. Forged reputation buys merge control, one
sync after the forgery.

### "Local is correct by construction" is false today

`oct` is a common ancestor, so it is always in our own history.
The tempting conclusion is that it needs no checking. It does,
because local history is not all ours:

- **fast-forward** -- `merge --ff-only rem` makes their whole
  branch our history; the FF check verifies one commit, the tip
- **diverge** -- the loser's commits arrive as parent-2, state
  files included
- **clone** -- `chains add --clone` validates nothing at all

The test proves it: the forged commit ends up in the victim's own
log. The shortcut is circular -- we trust `oct` because local is
correct, and local is correct because we never checked.

**This plan makes the premise true, which is what earns the
shortcut.**

## 2. Why the branch fix is a way-station

`260802-bug-forged-state` compares a commit's tree against the
REPLAY's accumulated `G`. That is replay-relative, and it forces
two exclusions:

- **side branches cannot be checked.** A merge side can fork BELOW
  `oct` -- B's post hanging off genesis while `oct` sits above it
  (`tst/bug-climb-ancestor`) -- so its tree is relative to a
  baseline the replay never had. Hence the `chk` flag threaded
  through `climb`/`meet`, off for both sides of every `meet`.
- **`order` cannot be checked.** See §6.
- **merge commits cannot be checked.** Found by `tst/sync.lua`
  step 8, red on the branch as committed. The only merge on `main`
  is a beg-accepting `like`, built by `merge -X ours`, and that
  option decides only CONFLICTING hunks: our side changed no state
  since the fork (step 5) => git takes THEIRS; both changed
  (step 8) => OURS. So the tree holds the beg side's state or our
  own depending on timing, and neither is the replay's. Same
  shape, opposite outcome. Exempted by `#parents(hash)==1`.

The intricacy is not incidental: it is what replay-relative
comparison costs.

Parent-relative needs none of the three. The beg merge verifies
as `apply(state(M) + beg entry from parent 2, like)`, which is
exactly what `chain like` computed when it built the commit.

## 3. The design: parent-relative

Verify a state commit against ITS OWN PARENT's committed state
plus the single action between them:

```
state(S) == apply( state(parent(S)), action(parent(S)) )
```

Both inputs are read from trees. No accumulated `G`, no knowledge
of where `oct` sits, no climb order. The baseline problem
disappears -- `be67e84` verifies against genesis, its actual
parent, and where the replay happens to be is irrelevant.

### Verification becomes a set, not a traversal

Because each check is self-contained, the unverified work is a set
difference:

```
git rev-list <new-tip> --not refs/freechains/verified
```

Every element can be checked in any order, in parallel, and the
result memoized forever -- "commit X is verified" is a fact about
content-addressed data and can never expire.

`refs/freechains/verified` is a single local ref: everything
reachable from it has been checked. Advance it after each
successful sync. Local and untracked, so no peer can forge it.
Reachability already expresses the whole set, so one ref is
enough.

The `rev-list` form also yields side branches pulled in by merges,
which a first-parent walk would miss -- and with a context-free
check those stop being a special case.

### Induction

A forgery cannot hide. Even a consistent forged RUN breaks at the
link where it meets honest history, and genesis anchors the base.
So: every link verified + trusted genesis => every ancestor sound
=> `oct` may be trusted without re-deriving it.

## 4. Separate verification from replay

Today `commit()` fuses two different jobs. Splitting them is most
of the win:

| Check | Kind | Cacheable |
|---|---|---|
| signature (`ssh.verify`) | context-free | yes |
| create-mode / path set | context-free | yes |
| commit kind | context-free | yes |
| `now` vs `PEAKS(parents)` | context-free | yes |
| **state vs parent+action** | **context-free** | **yes** |
| `apply` -- reps sufficiency | order-dependent | no |
| `apply` -- time monotonicity vs `G.now` | order-dependent | no |
| `apply` -- duplicate / target existence | order-dependent | no |

Everything context-free moves into the standalone pass over the
`rev-list` set, done once per commit ever. `climb`/`meet` keep
only what genuinely needs replay order.

That deletes the `chk` parameter, the side-branch exemption, and
the FF-only comparison at sync.lua:485-493.

## 5. Scope: FF, diverge and clone become one operation

All three reduce to "verify the set that is not yet reachable from
the frontier":

| Path | Frontier | Cost |
|---|---|---|
| diverge | recent | the incoming branch |
| fast-forward | recent | the incoming branch, INCLUDING interior commits the tip check misses |
| clone | empty | genesis..tip, once |

Clone is the base case of the induction and the one hole nothing
else closes. It is O(history) exactly once, after which the
frontier makes it incremental.

## 6. Two limits

### Merge links are not O(1)

For a merge commit `M` with parents `p1`, `p2`:

```
state(M) == combine( state(p1), state(p2) )
```

`combine` means re-deriving the consensus order between the sides
and applying one side's actions onto the other's state -- a replay
of one side, not a single `apply`. No stored state short-circuits
it, because the combined result equals nothing anyone stored.

So the pass is a hybrid: O(1) along linear stretches,
replay-one-side at each merge. `consensus()` and `octopus()` stay
in the picture for verification even though `climb`/`meet` do not.
Measure this before committing to the design -- it is the only
part whose cost is not obvious.

### `order` stays excluded

Blocked on a separate, pre-existing bug: two honest peers settle
on DIFFERENT orders for the same posts. In `tst/bug-climb-ancestor`
peer A ends with `[p1,p2,...]` and peer D with `[p2,p1,...]`
permanently -- the two entries that forked at genesis, swapped.
Confirmed by disabling the check and diffing both peers'
`order.lua`.

That test only asserts D's order HOLDS every post, never the
ordering, so it passes. Until consensus is actually deterministic
there, comparing `order` is a false rejection rather than a check.
It contradicts consensus.md's premise, and `hardfork()` compares
settled order prefixes, so it may fire spuriously or fail to fire.
Own bug, own fix.

## 7. Relation to the alternatives

**Never trust the tree** (drop `G_oct`, keep a local commit->state
cache, replay from the newest cached ancestor) deletes the attack
class rather than checking for it, and needs no verification code.
It is the cleaner endpoint. It was not taken because it makes
committed state vestigial, which pulls against
[260802-redesign.md](260802-redesign.md), where every commit
carries state by design.

The two converge more than they look: once this plan walks up to a
frontier, verifying a link is the same computation as replaying
that step, plus a read and a comparison. The comparison buys one
thing, and it is not correctness -- it DETECTS that a peer
published a lie instead of silently ignoring it. Worth keeping as
an alarm, and as input to reputation later.

A `Freechains-state-hash` trailer (option B in state-hash.md) is a
cheaper comparison, not a trust model: whoever forges the state
forges the trailer. Only ever an optimisation on top of this.

## 8. Steps

1. **DONE** `state_link(hash)` in chain/common.lua: read
   `state(parent)`, apply the one action, compare. Not yet wired
   (step 3/5); `state_diff` still in place, to be removed then.
   - helpers `tree_raw`, `tree_state`, `action` (all file-local)
   - `beg` recovered from the parent's reps, not from context
   - beg-`like` merge: target entry injected from parent 2
   - `now`/`order` excluded, `authors`/`posts` compared
2. Merge case: `state_merge(hash)` -- `consensus` over the two
   parents, replay the loser side, compare.
3. `verify(set)`: standalone pass over
   `git rev-list <tip> --not refs/freechains/verified`; move the
   context-free checks (§4) out of `commit()` into it.
4. `refs/freechains/verified`: create, advance after each
   successful sync, never push.
5. `sync.lua`: run `verify` before replay; drop the `chk`
   parameter, the side-branch exemption, the merge exemption
   (`#parents(hash)==1`, §2) and the FF comparison at
   sync.lua:485-493.
6. `chains.lua`: run `verify` after `--clone` -- the base case.
7. Tests: keep `tst/bug-forged-state.lua` (both cases); add an
   interior forgery reached only through a merge SIDE, which the
   branch version cannot catch and this one must.

Steps 1-3 are self-contained: the pass can land and run alongside
the existing checks before anything is deleted.

## 9. Open questions

- **What does a merge link actually cost?** §6. If it is bad, the
  fallback is to treat merge commits the "never trust" way --
  recompute rather than verify -- which is a small hybrid, not a
  redesign.
- **Does the frontier survive `destroy`?** destroy.lua resets past
  commits that stay verified; the ref must move back with it or it
  will point at a commit no longer on the branch.
- **Should a failed verification be fatal or an alarm?** Fatal for
  the anchor path. For a peer that merely published a bad record
  we already ignore, an alarm is more useful than a refusal.
- **Does `now` stay a separate check?** It is context-free and
  already implemented; folding it into `state_link` is tidier but
  changes an error message tests assert on.
