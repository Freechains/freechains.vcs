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
threshold. The attacker's node permanently freezes its
own ordering; the rest of the network has a different
frozen ordering.

**Resources**: Minimal — 1 rep per post, just needs to
stay offline. A pioneer with 30 rep can post 30 times
over 7 days trivially.

**Real threat**: Low in well-connected networks (peers
notice the absence), but **trivial to execute** and
**permanent in effect**. Any node that syncs with the
attacker inherits the fork, risking a cascading split.

**Impact**: Permanent consensus divergence. Reputation
computations differ across the split. Posts LINKED on
one side may be BLOCKED on the other.

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

**Mitigation direction**: Replace the hard 7-day cutoff
with a continuous decay function (see 7-day.md). No
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

---

## T2. Timestamp Manipulation

### T2a. Backdating Posts

**Mechanism**: Set `GIT_COMMITTER_DATE` to 12+ hours in
the past when creating a post. The post arrives at peers
appearing already matured — the 12h community reaction
window is bypassed. Other users cannot dislike it in time
because the window has apparently already elapsed.

**Resources**: None beyond posting ability (1 rep).

**Real threat**: High — **no validation is currently
implemented**.

**Impact**: Bypasses the community's reaction window.
The 12h rule exists so posts sit visible in the DAG long
enough for the community to evaluate and potentially
dislike them. Backdating skips this window entirely —
the post arrives looking settled.

**Mitigation**: Monotonic parent rule
(`commit.timestamp >= parent.timestamp`) is necessary
but insufficient. The attacker can post on a stale
branch (parent 12+ hours old) with a valid monotonic
timestamp and the post arrives looking already settled.
A past tolerance rule cannot help — freechains is
local-first, so nodes may legitimately be offline for
days or weeks. Rejecting old timestamps would break the
core design.

**Status**: Open. The monotonic rule prevents arbitrary
backdating (can't go before parent), but the stale
branch variant remains exploitable.

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

---

## T3. Reputation Attacks

### T3a. Sockpuppet Reputation Farming

**Mechanism**: A pioneer (30 rep) creates sockpuppet
identities and transfers rep via likes. After one hop:
- Pioneer spends 1 rep (cost) + transfers N rep
- 10% tax burns N*10%
- Sockpuppet receives N*90% (split between post/author)

With a +15 like: pioneer pays 1 cost, sockpuppet
receives 15 * 900 / 2 = 6750 internal (6 external) to
author + 6750 to post. Net: sockpuppet has 6 rep from a
single like.

**Resources**: Pioneer status or accumulated reputation.

**Real threat**: Medium — the 10% tax and cost make it
expensive but not prohibitive. A 30-rep pioneer can
bootstrap ~2-3 sockpuppets with meaningful reputation
before exhausting their own.

**Impact**: Sybil presence in the chain. Sockpuppets can
post, vote, and participate as if they were independent
users.

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
in consensus at its original timestamp position.

**Resources**: Two colluding accounts, one with rep.

**Real threat**: Medium — allows inserting content at
arbitrary historical positions in the consensus ordering.
Other users may have already read and acted on a timeline
that didn't include this post. The post materializes
after the fact.

**Impact**: Context manipulation. A reply that made sense
in one ordering becomes confusing when an earlier post
appears retroactively.

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

---

## Threat Summary Matrix

| ID   | Threat                        | Severity | Likelihood | Implemented? |
|------|-------------------------------|----------|------------|--------------|
| T1   | 7-day partition fork          | High     | Low        | No defense   |
| T1a  | Boundary attack               | High     | Medium     | No defense   |
| T1b  | Equivocation (100-post)       | High     | Low        | No defense   |
| T2a  | Backdating posts              | High     | High       | Partial      |
| T2b  | Future-dating posts           | Medium   | Medium     | Tolerance    |
| T2c  | Timestamp ordering            | Medium   | Medium     | Planned      |
| T3a  | Sockpuppet farming            | Medium   | Medium     | Partial (tax)|
| T3b  | Rep cycling                   | Low      | Low        | Yes (tax)    |
| T3c  | Retroactive BLOCKED→LINKED    | Medium   | Medium     | No defense   |
| T4a  | Merge-induced divergence      | High     | Low        | No defense   |
| T4b  | 12h maturation divergence     | Low      | Medium     | Accepted     |
| T5a  | Private key compromise        | High     | Low        | No defense   |
| T5b  | Personal key theft            | High     | Low        | No defense   |
| T6a  | Disk exhaustion via fetch      | Medium   | Medium     | Planned      |
| T6b  | Ref manipulation              | Low      | Low        | By design    |

---

## Priority Recommendations

1. **Implement timestamp validation** (T2a, T2b, T2c) —
   monotonic parent + 1h future tolerance. Blocks the
   cheapest attacks.

2. **Add deterministic tiebreaker for same-timestamp
   commits** (T4a) — e.g., lexicographic commit hash.
   Prevents silent honest-peer divergence.

3. **Replace 7-day hard cutoff with continuous decay +
   checkpoint commits** (T1, T1a) — continuous decay
   removes the sharp boundary; checkpoint commits
   (trust ring via DAG) ensure peers unanimously agree
   on when local-wins applies. See 7-day.md.

4. **Add size limits to non-owner fetch validation**
   (T6a) — max payload size, max commits per fetch.

5. **Design key revocation** (T5a, T5b) — at minimum,
   a "chain retired" marker that honest peers respect.

## Related Plans

- [7-day.md](7-day.md) — Deep analysis of the 7-day rule
  and continuous decay alternative
- [consensus.md](consensus.md) — Merge ordering rules
- [time.md](time.md) — Timestamp trust model and 12h rule
- [reps.md](reps.md) — Reputation system
- [replication.md](replication.md) — Owner vs non-owner sync
