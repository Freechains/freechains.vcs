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

**MEASURED.** `state_merge` re-derives from the boundary octopus
below both parents, anchored at ITS committed state, so it is
still context-free -- just not O(1). Suite timings, before/after:

| test | before | after |
|---|---|---|
| `fork-100-posts` (long, linear) | 18.1s | 17.9s |
| `bug-climb-ancestor` (nested merges) | 2.5s | 3.9s |
| `consensus` | 4.2s | 6.9s |
| `cli-list` (clone-heavy) | 4.6s | 8.8s |

Linear history is free -- the frontier keeps it incremental.
Merge- and clone-heavy paths run +60..90%. Acceptable; the
fallback in §9 is not needed.

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

All DONE. Suite green: 37/37 from source.

1. `state_link(hash)` in chain/common.lua: read `state(parent)`,
   apply the one action, compare.
   - helpers `tree_raw`, `tree_state`, `clone`, `state_same`,
     `action` (all file-local)
   - beg-`like` merge: target entry injected from parent 2
   - `now`/`order` excluded, `authors`/`posts` compared
2. `state_merge(hash)`: replay from `octopus(p1,p2)`, anchored at
   that commit's committed state. Cost measured, see §6.
3. `check(hash)` (context-free) split out of `commit()`, which is
   gone; `play(G,hash,beg)` keeps the order-dependent half.
   `verify(tip)` walks `rev-list --reverse <tip> --not <frontier>`.
   `ancestor`/`octopus`/`consensus`/`replay` moved to common.lua.
4. `refs/freechains/verified`, advanced by `frontier(tip)` after
   each sync, after a clone, and back again after `destroy`.
5. `sync.lua`: `verify` runs on `rem` AND on every `refs/begs/*`
   before anything reads a tree. `chk`, the side-branch exemption,
   the merge exemption and the FF comparison are all gone.
6. `chains.lua`: `verify` after `--clone`, the base case; the
   clone is removed again if it fails.
7. `tst/bug-forged-state.lua`: third case added -- a forged beg
   `state` commit merged in by a positive `like`, so it is
   reachable ONLY as parent 2 of a merge, with an honest tip. The
   branch version accepts it; this one refuses it.

### Two bugs found on the way

- **beg merges** (§2): `state_diff` false-rejected them, red on
  the branch as committed.
- **`CMD.now` vs the commit date.** `apply` recorded `CMD.now`
  while the commit took a SECOND wall-clock reading, so state
  could land one second off its own commit -- and every replay
  reads `%at`, not `CMD.now`. Parent-relative verification made it
  deterministic instead of a race. Fixed in `src/freechains.lua`:
  the date is now always pinned to `CMD.now`, not only under
  `--now`.

### Ambiguity that had to be resolved

A signed `post` is a beg or not, and nothing in the commit says
which -- `chain post` rejects the wrong one by the author's reps,
but the DAG keeps no record of the flag. `action` therefore
returns BOTH readings and `state_link` lets the recorded state
pick. A forger gains nothing: claiming the beg reading means
recording a beg, which is worth no reputation until someone likes
it.

When neither reading explains the record, the error to report is
the one that names the real fault: `posts` records WHAT the action
did, so a reading that reproduces it is the reading the author
meant, and its remaining mismatch is the complaint (a forged beg
records the beg correctly and lies only in `authors`). When no
reading gets that far, the plain reading's `apply` error is the
diagnosis -- the same words the replay used, which is what
`tst/err-post.lua` reads.

## 9. Open questions

- ~~**What does a merge link actually cost?**~~ Measured, §6.
  +60..90% on merge- and clone-heavy paths, flat on linear
  history. The "never trust" fallback is not needed.
- ~~**Does the frontier survive `destroy`?**~~ No -- destroy.lua
  now calls `frontier("HEAD")` after its reset, or the ref would
  point at a commit off the branch and hold it alive.
- ~~**Does `now` stay a separate check?**~~ Yes, but it moved
  AFTER the link inside `check`. A state commit with wrong values
  usually has a wrong `now` too, and of the two only the link can
  name what went wrong -- it re-runs the action and reports its
  `apply` error verbatim.
- **Should a failed verification be fatal or an alarm?** Still
  open. Fatal today, on every path. For a peer that merely
  published a bad record we already ignore, an alarm would be more
  useful than a refusal.
- **`order` is still excluded**, §6. Own bug, own fix.
- **Begs are re-verified every sync.** The frontier is reachability
  from `main`, and a beg is not reachable until a `like` merges it.
  Two commits each, so it is cheap, but it is not free.
