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

## References

- SBSeg-23 paper: `fsantanna-no/sbseg-23` — Section on
  consensus merge rules
- [consensus.md](consensus.md) — Hard fork rule and merge
  ordering
- [reps.md](reps.md) — Reputation system and pioneer setup
