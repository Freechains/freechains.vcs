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

## References

- SBSeg-23 paper: `fsantanna-no/sbseg-23` — Section on
  consensus merge rules
- [consensus.md](consensus.md) — Hard fork rule and merge
  ordering
- [reps.md](reps.md) — Reputation system and pioneer setup
