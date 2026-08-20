# Threat Analysis: Freechains 0.11 (Git Backend)

## Overview

This document catalogs security threats specific to the
git-backed Freechains architecture. Each threat includes
the attack mechanism, required resources, real-world
impact, and mitigation status.

---

## T1. Deliberate Hard Fork via Network Partition

**Mechanism**: An attacker disconnects from the network
for 7+ days while posting to their local branch. On
reconnection, the local branch has crossed the activity
threshold, so the attacker's node REFUSES every divergent
sync (`ERROR : chain sync : hard fork`). It permanently
freezes its own ordering and stops absorbing anyone.

**Resources**: Minimal — 1 rep per post, just needs to
stay offline. A pioneer with 30 rep can post 30 times
over 7 days trivially.

Note (span rule): entrenchment is now the SPAN of the
commits exclusive to the local branch, so staying offline
alone no longer suffices — the attacker must produce
commits at BOTH ends of the window.
That is still cheap: every commit kind counts, including
the `merge`/`state` pair a `sync recv` writes, so 1 post
now plus any sync 7 days later is enough. The cost of the
attack is therefore the 7-day wait, not the posting.

**Real threat**: Low in well-connected networks (peers
notice the absence), but **trivial to execute** and
**permanent in effect**. The refusal is visible (an error,
not silent divergence), which limits the cascade: honest
peers still merge the attacker's branch by consensus and
stay consistent with each other. It is the attacker that
isolates itself.

**Impact**: Permanent CONTENT partition on the attacker's
side, not merely an ordering disagreement. The attacker
keeps broadcasting but never receives again (its span only
grows), so its reputation view and post set drift from the
network's for good.

**Residual**: the span counts any commit exclusive to the
branch — any author's content pulled from third parties,
and the branch's own `merge`/`state` bookkeeping. A peer
that never authors anything can therefore entrench purely
by merging over time. That is intended (rule 1 protects
the ORDERING, not the content), but it means entrenchment
is cheap to acquire.

**Note (honest peers)**: the same mechanism fires without
an attacker. Any peer that is simply away long enough
(mobile, intermittent) crosses the threshold and then
refuses to reconcile, permanently. Under this design the
availability cost to honest absentees is arguably larger
than the value of the attack itself.

**Mitigation status**: None implemented. See T1a below.

---

## T1a. Boundary Attack on 7-Day Threshold

**Mechanism**: Attacker with legitimate prefix reputation
(>50%) creates one branch and controls delivery timing:

- Delivers to peer A at 6.999 days (below threshold) —
  rule 2 applies, attacker's branch wins on prefix rep
- Delivers to peer B at 7.001 days (above threshold) —
  rule 1 applies, local branch wins unconditionally

Both peers applied the rules correctly. Permanent fork.

**Resources**: >50% of prefix reputation at the fork
point. One branch. Precise delivery timing.

**Real threat**: High for chains with concentrated
reputation (1-2 pioneers, or one dominant author).
**Does not require network partition** — just controlled
delivery timing within one sync interval.

**Impact**: Same as T1 but harder to detect — no obvious
spam, no equivocation, just one branch arriving at
slightly different times.

**Status (span rule + refusal)**: NEUTRALISED as described.
Entrenchment is the span of the branch's own exclusive
commits, all frozen in the DAG, so it does not depend on
when the branch is delivered: peers A and B compute the
SAME verdict no matter the timing. Rule 1 also no longer
orders anything — it only decides whether the RECEIVER
merges — so controlling delivery cannot make two receivers
adopt different orderings of the same content.
The sharp threshold itself remains: a branch whose span
sits near `fork.time` still flips on one extra commit,
and two peers holding DIFFERENT subsets of the branch can
still disagree (the subset changes `exc`).

**Mitigation direction**: Replace the hard 7-day cutoff
with a continuous decay function (see 260723-fork-7day.md). No
sharp boundary means no exploitable threshold.

---

## T1b. Equivocation Attack (100-Post Threshold)

**Mechanism**: Attacker with 200+ reputation creates two
different branches (X and Y) of 100+ posts each.
Delivers X to peer A, Y to peer B. Both merge and cross
the 100-post threshold. When A and B sync, each ordering
is already frozen.

**Resources**: 200+ reputation (100 posts per branch at
1 rep each). Achievable for long-standing members.

**Real threat**: Medium — requires substantial reputation
but no network partition. Detectable (same author, 200
simultaneous posts, two incompatible branches).

**Impact**: Permanent fork. But equivocation is blatant
and recovery (revert to common prefix) is
straightforward.

**Note (span rule + refusal)**: the count axis now counts
commits EXCLUSIVE to the branch (`rev-list rem..loc`), so
commits the other side already holds do not inflate it.
The attack still works — the two equivocated branches are
exclusive to each other by construction — but its effect
changes: A and B now REFUSE to merge each other rather
than merging into two different orderings. The split is an
explicit error instead of a silent divergence.

---

## T2. Timestamp Manipulation

### T2a. Backdating Posts on Offline Branches

**Mechanism**: Post on a stale branch (parent 12+ hours
old) so the post's timestamp bypasses the 12h penalty
window and 24h consolidation reward. The post arrives at
peers appearing already settled — penalty expired,
reward collected.

Only offline branches can be exploited: the monotonic
parent rule (`commit.timestamp >= parent.timestamp`)
prevents arbitrary backdating, so the attacker needs a
parent whose timestamp is already old. A past tolerance
rule cannot help — freechains is local-first, so nodes
may legitimately be offline for days or weeks.

**Resources**: None beyond posting ability (1 rep) and
an offline branch.

**Real threat**: Medium. The attack only works on offline
branches, which are inherently weakened by the consensus
mechanism:

1. **Consensus ordering** — branches are ordered by
   prefix reputation (SBSeg-23, Section 2.1). An offline
   branch with fewer reputed authors is ordered after the
   majority branch. Posts in the secondary branch are
   applied later and may be rejected if operations
   conflict.

2. **Reactive defense** — the paper's stated defense
   (Section 2.2): users in the majority branch can post
   dislikes after seeing the offline branch, invalidating
   its posts. The attacker bypasses the *timestamp-based*
   reaction window, but the *consensus-based* defense
   still applies.

3. **Visibility** — offline branches are conspicuous.
   A branch that was disconnected for 12+ hours is
   already suspect. The longer the disconnection, the
   weaker the branch's consensus weight.

**Impact**: Bypasses the 12h/24h time-based rules, but
the consensus ordering and reactive dislike mechanism
provide a secondary defense. The attacker gains a timing
advantage (post appears settled on arrival) but cannot
override the majority branch's reputation.

**Gap in paper**: The SBSeg-23 paper assumes honest
timestamps and does not discuss timestamp manipulation.
The time-based rules (12h penalty, 24h reward) are
bypassable on offline branches, but the paper's
consensus defense was designed for exactly this scenario
(offline branches rejoining).

**Status**: Partially mitigated by consensus ordering.
The monotonic rule prevents arbitrary backdating. Offline
branches are weakened by design. The time-based rules
add defense in depth but are not the sole protection.

**Unreviewed idea — merge-witness timestamps**: Use the
earliest merge commit that witnesses a post as a lower
bound on its network arrival time. Time-based rules
(12h penalty, 24h reward) would use
`max(post_timestamp, first_merge_witness_timestamp)`
as the effective time, not the author's claimed timestamp.

- Rationale: the merge is created by the *receiving* peer,
  not the author. The author cannot control it.
- A backdated post would have a large gap between its
  claimed timestamp and its first merge witness → the
  gap itself signals manipulation.
- Weakness: if the first receiver colludes with the author,
  both timestamps can be forged. Raises cost from 1 node
  to 2 colluding nodes, and leaves an auditable trail
  (the fake merge is permanently in the DAG).
- Does not solve T2a, but makes it more expensive and
  detectable. NOT REVIEWED.

### T2b. Future-Dating Posts

**Mechanism**: Set a post's timestamp into the future.
The post appears in `--date-order` traversal at a later
position than it should, affecting consensus ordering
and reputation flow.

**Resources**: None beyond posting ability (1 rep).

**Real threat**: Medium — bounded by the 1-hour future
tolerance (`commit.timestamp <= receiver.local_time + 1h`).
At most ~1 hour of manipulation, which is < 9% of the
12h maturation window.

**Mitigation**: Future tolerance rule rejects commits
with timestamps more than 1 hour ahead of the receiver's
local clock.

### T2c. Timestamp Manipulation of `--date-order`

**Mechanism**: Forge timestamps to control where posts
appear in the consensus traversal. A post with a
backdated timestamp appears earlier in the ordering,
potentially changing reputation flow for all subsequent
posts.

**Resources**: None beyond posting ability.

**Real threat**: Medium — affects consensus ordering but
bounded by monotonic parent rule once implemented.

### T2d. Moving the Settled Line via `merge`/`state` Dates

**Mechanism**: `hardfork` measures the settled prefix over
`order.lua` entries, reading each one's `%at`. The dates of
`merge` and `state` commits are pusher-controlled: `sync
send` forwards `--now` as `-o now=`, and the receiver's
pre-receive hook pins its `recv` to that value. A pusher who
could get such a commit into `order.lua` would set the
timestamp that defines the receiver's `fork.time` window,
either freezing a prefix that should still reorder or
thawing one that should be settled.

**Mitigation**: `order.lua` holds only `post`, `like`, and
`revoke` — the kinds appended by `commit` in `sync.lua`.
`state` falls to the `else` branch, which only verifies the
recorded peak and appends nothing; `merge` never reaches
`main` at all (built on a detached head, then discarded).
So no pusher-dated commit is ever on the axis `hardfork`
measures.

**Real threat**: Low as implemented — but the property is
structural and easy to break by accident: any future kind
appended to `G.order` must have a date the receiver derives,
not one the sender supplies.

---

## T3. Reputation Attacks

### T3a. Sockpuppet Reputation Farming

**Mechanism**: A pioneer (30 rep) creates sockpuppet
identities and transfers rep via likes.

**Resources**: Pioneer status or accumulated reputation.

**Real threat**: **Low** — sockpuppets do not amplify
voting power. A like of +N costs 1 rep and delivers
N×900 internal regardless of who sends it. Splitting
votes across 3 sockpuppets (3 likes of +1 = 3 rep cost,
2700 delivered) is strictly worse than 1 like of +3
(1 rep cost, 2700 delivered). The system is purely
arithmetic on reputation values — there is no rule
that treats number of distinct voters differently from
vote magnitude. Sockpuppets dilute, not amplify.

**Impact**: Minimal. Sybil presence exists but confers
no advantage over a single account with the same total
reputation.

### T3b. Reputation Cycling (A→B→C→A)

**Mechanism**: Three colluding accounts cycle likes among
each other to inflate reputation.

**Resources**: Initial reputation for all three accounts.

**Real threat**: Low — the 10% tax per hop means each
cycle loses ~27% of value (0.9^3 = 0.729). After 3-4
full cycles the reputation is nearly depleted.
Self-limiting.

### T3c. BLOCKED→LINKED Retroactive Insertion

**Mechanism**: Author posts while at 0 rep (post is
BLOCKED/invisible). Later receives likes from an
accomplice. Post retroactively becomes LINKED — appears
in the DAG at its original position.

**Resources**: Two colluding accounts, one with rep.

**Real threat**: **Low** — this is only a concern if
users interpret the chain chronologically by timestamp.
The DAG tells the real story: cause-effect is explicit
in parent references. When A's post becomes LINKED, no
existing post has it as a parent — the DAG proves
nobody saw it when they acted. The "retroactive
insertion" is a UI/presentation issue, not a protocol
threat. If the client shows DAG causality (parent
links), there is nothing to exploit.

**Impact**: Minimal at protocol level. A client that
sorts purely by timestamp could mislead users, but
that is a client design choice, not a consensus flaw.

---

## T4. Merge-Induced Non-Determinism

### T4a. DAG Divergence from Peer-Specific Merge Commits

**Mechanism**: Each peer creates unique merge commits
when syncing. Peer A syncing with B creates M_AB; peer C
syncing with B creates M_CB. These are different commits
with different hashes and timestamps. After full
propagation, peers have structurally different DAGs.

`git log --date-order` traverses the full DAG. When two
content commits share the same Unix-second timestamp,
traversal order depends on which DAG path was followed
first — which depends on merge commit structure — which
differs per peer.

**Resources**: None — this is normal operation.

**Real threat**: Low but nonzero — requires timestamp
collision (same Unix second). Probability increases with
posting frequency. A chain with high throughput (multiple
posts per second) would hit this regularly.

**Impact**: Honest peers compute different consensus
orderings → different reputation → different
BLOCKED/LINKED decisions. **Permanent silent divergence**
with no attacker involved.

**Mitigation**: The design skips merge-only commits in
consensus computation, but `--date-order` still uses them
for traversal. A deterministic tiebreaker (e.g., commit
hash) for same-timestamp content commits would eliminate
this. Alternatively, computing consensus over the content
DAG only (ignoring merge commits entirely in traversal)
would match the original Freechains behavior.

### T4b. 12h Maturation Temporary Divergence

**Mechanism**: A like with timestamp T is fetched by
node A at T+12h+1min (mature → reputation visible) and
by node B at T+12h-1min (not mature → no effect). Posts
depending on that reputation are accepted by A, rejected
by B.

**Resources**: None — normal timing variation.

**Real threat**: Low — temporary only. Git fetch
transfers all objects regardless; once 12h passes, both
nodes converge. Bounded disagreement window.

**Impact**: Confusing UX (fetch fails, retry later
succeeds). Cascading temporary disagreement for
dependent posts.

**Mitigation status**: Accepted as a design tradeoff
(time.md). Read-time validation is correct despite
temporary non-determinism.

---

## T5. Chain-Type-Specific Threats

### T5a. Private Chain Key Compromise

**Mechanism**: The shared X25519 key for a `$` private
chain is leaked. All holders have infinite reputation
and no signing requirement.

**Resources**: Access to the shared key.

**Real threat**: Standard symmetric-key risk. No
revocation mechanism documented — compromised key means
the chain is permanently compromised.

### T5b. Personal Chain Key Theft

**Mechanism**: An `@` personal chain's Ed25519 key is
stolen. The thief has infinite reputation and can post
as the owner.

**Resources**: Access to the private key.

**Real threat**: Standard asymmetric-key risk. Same
absence of revocation.

---

## T6. Git-Layer Threats

### T6a. Object Injection via Fetch

**Mechanism**: `git fetch` unconditionally transfers
objects. A malicious peer could send large objects or
many commits to exhaust disk space or slow consensus
computation.

**Resources**: Network access to the victim peer.

**Real threat**: Medium — git has no built-in size limits
per fetch. The planned non-owner validation would add
size checks, but it's not yet implemented.

### T6b. Ref Manipulation

**Mechanism**: A malicious git remote could advertise
refs pointing to crafted commits that pass git validation
but violate freechains rules.

**Real threat**: Low — freechains validates between fetch
and merge. The fetch-then-validate-then-merge pipeline
is correct by design.

### T6c. Remote Lua Executed as a Program

**Mechanism**: `chains add clone` fetches `refs/genesis`
and `git reset --hard` writes the remote's `genesis.lua`
into the worktree (`chains.lua`). `pioneers()` then read
it with `dofile`, i.e. with the full global environment:
a hostile peer's genesis could call `os.execute` on the
cloning machine. `chain get payload` had the same shape
over the REMOTE-authored action file (`get.lua`), where
passing the sandboxed check in `sync` does not neutralise
bytes that a later call re-loads with globals.

**Resources**: Any peer the victim chooses to clone from,
or any action that reached the victim through `sync`.

**Real threat**: was High — one line in a fetched file is
arbitrary code. `ACTION.read` already had the answer:
`load(out, "=action", "t", {})`, text only and no globals,
"the file is DATA, not a program".

**Mitigation**: both readers now use that same shape. A
genesis that is not a table is refused as `invalid
genesis`. `state.lua` still loads with globals, but
`refs/states/*` are written locally and never fetched:
reaching them means the attacker already owns the disk.

---

## T7. Free Self-Revoke Faucet

**Mechanism**: An author's self-revoke is free and ungated
(`rules.lua`: skips the reps gate and the cost, works at 0
reps). Nothing dedups it, so the author can re-revoke an
already-revoked action without limit. Each cast is a new
commit — unbounded free DAG growth that every peer must
store and relay. A `--why` blob rides along for free
payload bytes, and free actions count toward the 100-action
settling window (feeds T1b).

**Resources**: One admitted post (or beg) to become an
author; then zero reps thereafter.

**Real threat**: Medium — cheap, unmetered write
amplification. Distinct from T3 (rep economy) and T6a
(fetch-side): the commits are locally authored and valid.

Note: the post/revoke/post/revoke cycle is NOT a rep
attack — each post still costs and is reps-gated, and a
self-revoked post still refunds and consolidates normally
(the maturity clock ignores `is_revoked`). The faucet is
the free revoke commit itself, not the pairing.

**Mitigation**: A free self-revoke must change state — it
is rejected once the action's `revoke.author` sum is
already negative. One absolute right-to-be-forgotten cast
per action stands; an author who wants to toggle again
pays via `unrevoke` (which costs). Guarded in `rules.lua`.

---

## Threat Summary Matrix

| ID   | Threat                        | Severity | Likelihood | Implemented? |
|------|-------------------------------|----------|------------|--------------|
| T1   | 7-day partition fork          | Medium   | Low        | Self-isolates|
| T1a  | Boundary attack (timing)      | High     | Low        | Span rule    |
| T1b  | Equivocation (100-post)       | High     | Low        | No defense   |
| T2a  | Backdating offline branches   | Medium   | Medium     | Consensus    |
| T2b  | Future-dating posts           | Medium   | Medium     | Tolerance    |
| T2c  | Timestamp ordering            | Medium   | Medium     | Planned      |
| T2d  | Settled line via merge/state  | Low      | Low        | Order kinds  |
| T3a  | Sockpuppet farming            | Low      | Low        | By design    |
| T3b  | Rep cycling                   | Low      | Low        | Yes (tax)    |
| T3c  | Retroactive BLOCKED→LINKED    | Low      | Medium     | By design    |
| T4a  | Merge-induced divergence      | High     | Low        | No defense   |
| T4b  | 12h maturation divergence     | Low      | Medium     | Accepted     |
| T5a  | Private key compromise        | High     | Low        | No defense   |
| T5b  | Personal key theft            | High     | Low        | No defense   |
| T6a  | Disk exhaustion via fetch      | Medium   | Medium     | Planned      |
| T6b  | Ref manipulation              | Low      | Low        | By design    |
| T6c  | Remote Lua run as a program   | High     | Low        | Yes (sandbox)|
| T7   | Free self-revoke faucet       | Medium   | Medium     | Guard (dedup)|

---

## Priority Recommendations

1. **CRITICAL: Implement timestamp validation** (T2a,
   T2b, T2c) — This is the most dangerous open threat.
   T2a costs nothing, requires no collusion, and
   completely bypasses the 12h maturation rule. Without
   timestamp validation, the entire reputation system
   is hollow: an attacker backdates a like to 12h+ ago,
   the like appears already matured, and reputation
   inflates instantly. Every other defense (10% tax,
   12h maturation, post cost) assumes timestamps are
   honest. Monotonic parent rule + 1h future tolerance
   must be the first implementation priority.

2. **Add deterministic tiebreaker for same-timestamp
   commits** (T4a) — e.g., lexicographic commit hash.
   Prevents silent honest-peer divergence.

3. **Replace 7-day hard cutoff with continuous decay +
   checkpoint commits** (T1, T1a) — continuous decay
   removes the sharp boundary; checkpoint commits
   (trust ring via DAG) ensure peers unanimously agree
   on when local-wins applies. See 260723-fork-7day.md.

4. **Add size limits to non-owner fetch validation**
   (T6a) — max payload size, max commits per fetch.

5. **Design key revocation** (T5a, T5b) — at minimum,
   a "chain retired" marker that honest peers respect.

## Analysis Notes

- **T3a downgraded**: Sockpuppets do not amplify voting
  power. Like math is purely arithmetic — splitting
  votes across N accounts costs more than a single
  vote of the same magnitude. No rule distinguishes
  number of voters from vote size.

- **T3c downgraded**: Only exploitable if users trust
  timestamps over DAG causality. The DAG parent links
  prove that no existing post referenced the retroactive
  post — nobody saw it. A DAG-aware client eliminates
  this threat entirely.

- **T2a is the critical gap**: It undermines the 12h
  rule, which is the foundation for all reputation
  timing defenses. Until timestamps are validated,
  the reputation system operates on the honor system.

## Related Plans

- [260723-fork-7day.md](260723-fork-7day.md) — Deep analysis of the 7-day rule
  and continuous decay alternative
- [consensus.md](consensus.md) — Merge ordering rules
- [time.md](time.md) — Timestamp trust model and 12h rule
- [reps.md](reps.md) — Reputation system
- [replication.md](replication.md) — Owner vs non-owner sync
