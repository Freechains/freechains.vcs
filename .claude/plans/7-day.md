# The 7-Day Rule: Analysis and Attack Vector

## Why the 7-Day Rule Exists

From the SBSeg-23 paper (`fsantanna-no/sbseg-23`):

The rule defends against **offline reputation farming**. A
malicious user who is an established member (pioneer or
earned reputation) intentionally disconnects, creates fake
identities offline, farms reputation among them, then
reconnects with a branch full of fake reputation that could
"take over the majority of reps in the forum."

The 7-day/100-post threshold says: if the local branch has
been active past the threshold since divergence, the remote
branch can never reorder local history — regardless of
remote reputation.

## Why the Prefix Rule Alone Isn't Enough

The prefix reputation rule (rule 2) orders branches by
reputation in the common prefix. One might think this
already defeats offline farming — the attacker's fake
reputation only exists in their own branch, not the prefix.

But the paper's scenario involves an attacker who **already
has real prefix reputation** — they're an established
member who goes rogue. Their branch wins the prefix rule
legitimately.

A second scenario: legitimate users with prefix reputation
**abandon** the forum. Their dead branch could still win on
prefix reputation over the active community's branch.

The 7-day rule protects against: **a branch with legitimate
prefix reputation that no longer serves the active
community** — whether through malice or abandonment.

## Attack: Forcing Permanent Divergence with Frequent Sync

Assumption: the network is well-connected and correct peers
synchronize often. No network partition is possible.

### Why naive attacks fail

If peers sync often, the divergence point between any two
peers is always recent. Every sync resets the clock — after
merging, both peers share the same HEAD. A new fork starts
at 0 days, 0 posts. An attacker can't reach the 7-day
threshold, and the 100-post threshold seems hard to hit in
a small sync window.

### The attack that works

The attacker is a **legitimate, established member** with
abundant reputation (200+), accumulated through real
participation and received likes over time.

1. Attacker creates **branch X** with 100+ posts, delivers
   to peer A
2. Attacker creates **branch Y** (different content) with
   100+ posts, delivers to peer B
3. Both A and B merge — each local branch now crosses the
   **100-post threshold**
4. When A and B sync, each peer's ordering is already
   **frozen** — permanent fork

The attacker needs 200+ reputation (100 posts per branch at
1 rep each). This is achievable for a long-standing member
who has accumulated likes.

The critical point: this does **not** require a network
partition. The attacker just needs to deliver 100 posts to
each peer **within one sync interval**. With enough
reputation, they blast both peers simultaneously.

### The sharper attack: exploiting the 7-day boundary

The attacker doesn't need 100 posts or 200 reputation.
They exploit the **boundary condition** of the 7-day rule
itself.

The attacker has **legitimate prefix reputation** (enough
to win rule 2). They create **one branch** and control
delivery timing:

1. Delivers to peer A when A's local branch is at
   **6.999 days** — below threshold, so **rule 2 applies**:
   attacker's branch wins on prefix reputation, ordered
   first
2. Delivers to peer B when B's local branch is at
   **7.001 days** — above threshold, so **rule 1 applies**:
   B's local branch wins unconditionally

Peer A and peer B now have **permanently different
orderings** — and both applied the rules correctly. It's
not a bug in either peer, it's a boundary condition in the
protocol itself.

This is far more dangerous than the 100-post attack:

- Requires only **one branch**, not two
- Requires minimal reputation spend (the prefix reputation
  does the work)
- At peer A, the attacker's branch **reorders legitimate
  content** — real damage to consensus
- Harder to detect — not obvious spam, just a single
  branch arriving at slightly different times

### Who can execute this attack?

To win rule 2, the attacker's branch needs **more than
half of the total prefix reputation**. This means:

- **Pioneers**: a single pioneer in a 1-pioneer chain
  (30/30) trivially wins, but they already control the
  chain. In a 2-pioneer chain (15/30), one pioneer alone
  ties. In a 3-pioneer chain (10/30), one pioneer can't
  win alone.
- **Popular members**: any user who accumulated significant
  reputation through received likes.
- **Colluding groups**: any coalition holding >50% of
  prefix reputation.

The prefix reputation is **frozen at the fork point**. So
a group that held >50% at **any point in the past** could
use that historical snapshot as their fork point. They can
attempt the attack **at any time in the future** — the
old prefix doesn't change.

However, the fork point must be **recent (~7 days ago)**
for the boundary attack to work. If the attacker forks
from months ago, the community's local branch has long
crossed the 7-day threshold, so rule 1 applies and the
local branch wins unconditionally. The attacker must have
held >50% of reputation **at a point ~7 days before the
attack**.

This reduces to the standard Byzantine assumption: **a
majority coalition can attack the system**. This is true
of essentially every consensus protocol.

## Consequences of Both Attacks

Assuming peers A and B communicate soon after the attack:

### 1. Detection: easy

For the 100-post attack: obvious equivocation — same
author, 200 simultaneous posts, two different branches.

For the boundary attack: the attacker was **offline for
~7 days** in a network where correct peers sync often.
A 7-day silence followed by perfectly-timed delivery is
a strong signal. Not as blatant as equivocation, but
suspicious.

### 2. Recovery: revert to common prefix

Both peers share the same common prefix up to the fork
point. The protocol has no automatic mechanism to undo a
hard fork, but peers can manually revert to the common
prefix and discard the attacker's branch. The attacker's
identity is known (they were offline, they hold >50%
prefix rep). Out-of-band coordination is needed but the
path is clear.

### 3. Content damage: near zero

In both attacks, the only divergent content is the
**attacker's own**. The legitimate users' posts are all
in the common prefix — identical on both sides. Since
peers were syncing often, the fork point is very recent
(minutes for the 100-post attack, ~7 days for the
boundary attack but with the attacker offline the whole
time — no legitimate content was lost).

The attacker destroyed **their own reputation** and
caused an operational headache, but actual content loss
is near zero.

## Scope: Local-First vs Permanently Connected

The analysis above assumes **local-first** requirements — peers
operate offline, sync intermittently, and must resolve divergence
after the fact. This is the hard case.

For **permanently connected chains** (peers always online and
syncing continuously), the picture changes:

- **Content loss is solvable**: reducing the threshold (days or
  posts) eliminates the window where content can be trapped on
  the wrong side of a hard fork. With frequent sync and a low
  threshold, branches are short-lived and the common prefix is
  always recent — legitimate content is never at risk.
- **Divergence remains**: even with a reduced threshold, the
  **permanent divergence** attack still applies. The attacker
  can still deliver conflicting branches to different peers
  within a single sync interval, causing a hard fork. A lower
  threshold makes the 100-post variant harder (less time to
  generate posts) but the boundary attack adapts to whatever
  threshold is chosen — 1 day, 1 hour, any sharp cutoff is
  exploitable.

In short: permanent connectivity + low threshold solves the
**content loss** problem but not the **consensus divergence**
problem. The design alternatives below (continuous decay,
checkpoint commits) remain necessary for chains that require
Byzantine-resilient consensus, regardless of connectivity
assumptions.

## Toward a Replacement: Design Constraints

Analysis of alternatives to the 7-day rule, exploring what
can and cannot work.

### What we need

A rule that **breaks the symmetry** between two branches
at merge time, so all peers agree on ordering. The rule
must be:

1. **Deterministic** — all peers compute the same result
2. **Based on shared data** — not local state
3. **Resistant to boundary attacks** — no sharp threshold

### What doesn't work

**Prefix-only solutions**: At merge, the common prefix is
the only mutually trusted state. But any function applied
to prefix data yields identical results for both branches
— it can't break symmetry. Even reputation decay applied
uniformly to the prefix preserves relative ordering
(10 vs 5 decays to 5 vs 2.5 — same winner).

**Local state (read time)**: Using "when did I first
receive this branch" would break symmetry naturally —
content you've been reading wins over late arrivals. But
different peers have different read times → different
orderings → different reputation calculations →
**consensus breaks, spam wins**.

### What must be true

To break symmetry, you need data that:

1. **Differs between the two branches** (not just prefix)
2. **Is the same for all peers** (not local state)
3. **Is trusted** (embedded in commits, verifiable)

**Timestamps** are the only data fitting all three
criteria. They're embedded in commits, visible to all
peers, and differ between branches.

**A time-based rule is unavoidable.** The question is: can
we replace the hard 7-day cutoff with a **continuous**
function that has no exploitable boundary?

### Direction: continuous decay of advantage

Instead of a binary threshold, the prefix reputation
**advantage** decays continuously as a function of
divergence time:

```
divergence = max_timestamp(both branches) - fork_timestamp
advantage  = (rep_A - rep_B) * decay(divergence)
```

- Just forked: full advantage → higher prefix rep wins
- Over time: advantage shrinks toward zero
- Eventually: advantage → zero → tiebreaker needed

No sharp boundary. The 6.999 vs 7.001 attack becomes
meaningless — there's no moment where the rule flips.

**Tiebreaker problem**: when the advantage decays to zero,
something must break the tie. A **hash-based tiebreaker**
(lexicographic comparison of HEAD tips) does **not work** —
each peer has different commits on their local branch, so
they see different HEAD hashes. The hash is local state, not
shared data. Any tiebreaker must satisfy the same three
criteria from "What must be true" above: differs between
branches, same for all peers, embedded in commits. This is
an **open problem** for the decay approach alone — without
checkpoint commits or another shared-state mechanism, there
is no obvious deterministic tiebreaker once reputation
advantage reaches zero.

**Open questions**:

- What decay function? (linear, exponential, sigmoid?)
- What's the half-life? (replaces the 7-day constant)
- How does this interact with the 100-post threshold?
- What replaces the hash tiebreaker? (checkpoint commits
  may be the only viable answer)

### Direction: checkpoint commits (trust ring via DAG)

Instead of synchronous peer-to-peer queries, peers embed
their branch-maturity evidence **into the DAG itself** as
checkpoint commits.

#### Mechanism

When a peer's local branch crosses a maturity milestone
(e.g., N days of activity since fork point X), it posts a
**checkpoint commit** — a zero-payload signed commit:

```
tree 4b825dc...           (empty tree)
parent <HEAD>
author <pubkey> <timestamp>
committer <pubkey> <timestamp>
freechains-checkpoint: fork=<fork-hash> days=<N>

```

At merge time, the rule becomes:

1. Count checkpoint commits from **distinct authors** in
   each branch
2. If a **quorum** of peers have posted checkpoints for
   the same fork point with days >= threshold, **all peers
   agree** the branch is mature → local-wins applies
3. If you see NO checkpoints from others for your fork
   point, you might be isolated → fall back to local-wins
   defensively
4. If checkpoints disagree (some say mature, some don't),
   use the majority

#### Why this kills the boundary attack

The boundary attack (T1a) requires peers to independently
cross the 7-day threshold at different moments. With
checkpoint commits:

- Peer B crosses 7 days first, posts a checkpoint commit
- When peer A fetches, it sees B's checkpoint in the DAG
- A adopts local-wins **before** reaching 7 days itself
- Both peers now use the same rule → converge

**Key property**: "if ANY honest peer's checkpoint says
mature, ALL peers treat the branch as mature." The
protection kicks in at the earliest moment any peer would
trigger it — unanimously.

The attacker can't forge checkpoints from other peers
(they're signed). And the attacker can't suppress them
either — git fetch transfers all objects unconditionally.

#### Properties

- **DAG-embedded**: no synchronous network round-trip at
  merge time. Consensus remains derivable from the DAG
  alone
- **Signed**: checkpoints are authored commits, forgery
  requires the private key
- **Asynchronous**: peers post checkpoints independently
  as they observe branch maturity
- **Quorum-based**: attacker in the ring is outvoted by
  honest majority (standard Byzantine assumption)

#### Tradeoffs

- **Liveness dependency**: if peers don't post checkpoints
  (offline, lazy), the quorum may never form. Fallback:
  after a hard timeout (e.g., 14 days with no quorum),
  apply local-wins unconditionally
- **Information leakage**: checkpoint commits reveal which
  peers are active and when they observed divergence
- **DAG bloat**: extra zero-payload commits. Mitigated by
  posting checkpoints only near maturity thresholds, not
  continuously
- **Requires signing**: checkpoints must be signed to
  prevent forgery — chains without signing can't use this

#### Interaction with continuous decay

The two directions are **complementary**, not competing:

- **Continuous decay** eliminates the sharp boundary for
  the reputation-based ordering rule (rule 2) — no
  threshold to exploit
- **Checkpoint commits** provide peer agreement on WHEN
  to override reputation entirely (rule 1 / local-wins)
  — the transition is unanimous

Combined: reputation advantage decays continuously, AND
when a quorum of peers confirms maturity via checkpoints,
the transition to local-wins is unanimous. Neither
mechanism alone solves the problem fully; together they
cover both the gradual and the categorical cases.

## References

- SBSeg-23 paper: `fsantanna-no/sbseg-23` — Section on
  consensus merge rules
- [consensus.md](consensus.md) — Hard fork rule and merge
  ordering
- [reps.md](reps.md) — Reputation system and pioneer setup
- [threats.md](threats.md) — Full threat catalog (T1–T6)
