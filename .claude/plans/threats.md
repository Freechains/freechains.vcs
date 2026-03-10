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

### T2a. Backdating Likes

**Mechanism**: Set `GIT_COMMITTER_DATE` to 12+ hours in
the past when creating a like commit. The like appears
already matured to all receivers — 12h rule bypassed.

**Resources**: None beyond posting ability.

**Real threat**: High — **no validation is currently
implemented**. The planned monotonic parent rule bounds
backdating to the gap between parent timestamp and now,
but if the parent is old (e.g., chain was quiet for
hours), the gap is large.

**Impact**: Instant reputation inflation. Enables
reputation cycling (A likes B, B immediately spends new
reps) that the 12h rule was designed to prevent.

**Mitigation status**: Planned (time.md) — monotonic
parent rule + future tolerance. Not yet implemented.

### T2b. Future-Dating Likes

**Mechanism**: Set timestamp 12+ hours in the future.
The like appears mature on arrival.

**Resources**: None.

**Real threat**: Medium — bounded by the planned 1-hour
future tolerance (< 9% of the 12h window). Once
implemented, this attack gains at most ~1 hour.

**Mitigation status**: Planned — `commit.timestamp <=
receiver.local_time + 1h`. Not yet implemented.

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

---

## Threat Summary Matrix

| ID   | Threat                        | Severity | Likelihood | Implemented? |
|------|-------------------------------|----------|------------|--------------|
| T1   | 7-day partition fork          | High     | Low        | No defense   |
| T1a  | Boundary attack               | High     | Medium     | No defense   |
| T1b  | Equivocation (100-post)       | High     | Low        | No defense   |
| T2a  | Backdating likes              | High     | High       | Planned      |
| T2b  | Future-dating likes           | Medium   | Medium     | Planned      |
| T2c  | Timestamp ordering            | Medium   | Medium     | Planned      |
| T3a  | Sockpuppet farming            | Low      | Low        | By design    |
| T3b  | Rep cycling                   | Low      | Low        | Yes (tax)    |
| T3c  | Retroactive BLOCKED→LINKED    | Low      | Medium     | By design    |
| T4a  | Merge-induced divergence      | High     | Low        | No defense   |
| T4b  | 12h maturation divergence     | Low      | Medium     | Accepted     |
| T5a  | Private key compromise        | High     | Low        | No defense   |
| T5b  | Personal key theft            | High     | Low        | No defense   |
| T6a  | Disk exhaustion via fetch      | Medium   | Medium     | Planned      |
| T6b  | Ref manipulation              | Low      | Low        | By design    |

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
   on when local-wins applies. See 7-day.md.

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

- [7-day.md](7-day.md) — Deep analysis of the 7-day rule
  and continuous decay alternative
- [consensus.md](consensus.md) — Merge ordering rules
- [time.md](time.md) — Timestamp trust model and 12h rule
- [reps.md](reps.md) — Reputation system
- [replication.md](replication.md) — Owner vs non-owner sync
