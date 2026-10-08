# Goal

- reward period (24h consolidation) adapts to activity, as the
  quarantine (12h discount) already does
- busy chains (chat, 2-day conference) grow fast; quiet ones
  keep ~24h
- no per-chain constant
- keep rule 1.b "at most once per period": volume mints nothing

# Evidence (2606-sims, chat 5k, 26/10/08)

- 5000 posts in 35 days, 58 members, top member 1081 posts
- one settle per member per 24h: 4295 of 5000 posts still
  queued at the end (offline estimate: 87%)
    - same estimate with 1h: 25%; with 10 min: 0.5%
- reps of a heavy member climb 1K/day after the corpus ends
  (31.5K at end, 50K cap at +30 days)
- `reps` at a far `--now` folds every queued settle:
    - +1 day 0.15 s, +30 days 1.7 s, +16 years 22 s
- `find`/`nexthead` scan `G.pending` linearly per settle
- 2-day conference, 500 users: today admits ~250 at most
  (50K pioneers / 556 per like, +90K on day 2)

# Today (rules.lua `advance`)

- quarantine: refund 500 after
  `C.time.half * max(0, 1 - 2*ratio)`
    - ratio = reps of members acting after the post / total
- settle: per member, oldest 12-24 record once
  `time >= head + C.time.full`, one slot per `C.time.full`
- slot grid `last + full`: catches up after idle gaps
- queue: every record waits its turn, paid 1K/day forever
    - per-post emission in disguise, only delayed
    - reward without presence (years after the corpus)

# Rule (decided 26/10/08)

- a. no queue (depth 1)
    - settled record: credited if slot open; else parked if
      nothing parked; else consolidated, no credit
    - `last` = reward time (no grid)
    - revoked post still consumes the slot
    - one field per member holds the parked record
    - first slot of a member is open (no previous reward)
- b. slot in activity time
    - slot opens `C.time.full * max(0, 1 - 2*r)` after the
      last reward
    - `r` = reps of OTHER members acting after the last
      reward / reps of all other members
    - anchor = reward time, not post time
    - self excluded
- post settle: `C.time.full * max(0, 1 - 2*r_post)`,
  anchored at the post (plan's original rule)
- credit needs both: settled and slot open

# Why (discussed 26/10/08)

- plan's "slot advances by the same scaled period" hits 0
  at r >= 50%: 10 posts, one acknowledgement, 10 rewards
- anchoring at the reward makes each reward need a fresh
  half of the community acting after the previous one
- self excluded: majority holder would open own slot
- queue vs no queue incentives:
    - queue: flood now, paid anyway
    - no queue: hold a post until the slot opens
    - holding costs most where the slot reopens fastest
    - value is paid by likes (rule 3), presence by 1.b
- inverted times: bounded by `C.time.diff` (1h); only
  reorders which post wins the slot; anchor uses chain time
- 24h vs any constant: arbitrary; what matters is
  per period vs per post

# Behavior

- quiet chain: r ~ 0, ceiling 24h, as today
- busy chat: epoch of minutes to hours, 1K per epoch
- conference: short epochs, exponential admission
- 31 posts in one epoch: first to settle paid, rest free
- member idle then posting twice: one per day, not two at once

# Tests (26/10/08)

- new `tst/cli-slot.lua` (in Makefile after `cli-time`),
  all failing today:
    - slot-depth-1: 3 posts, pays day 1 and 2, not day 3
    - slot-no-catchup: idle 5 days, 2 posts, one per day
    - slot-anchor-one-reward: 10 posts, one ack, +1K at once
    - slot-anchor-second-ack: fresh ack reopens, dropped
      posts never pay
    - slot-self-excluded: 79% holder acting alone keeps 24h
    - slot-acceleration: 4 rounds of 4 posters, 4 rewards
- existing tests to revisit after (b):
    - `cli-like.lua`: KEY2's like settles KEY1's post at
      once, +1K on the next command (~6 numbers)
    - `cli-revoke.lua` ln 220, 268: "not consolidated" may
      no longer hold after the other member's action
    - `cli-revoke-earn.lua`: "before 24h" block becomes
      "after" (revoker holds 50%); re-time or use GEN_3
    - consensus/fork tests: no reps asserts, run to confirm
- `cli-time.lua` 1-per-day: capped at 50K, never observed
  the queue; add a day-2/3 check after spending

# Economics (checked 26/10/08)

- implicit acknowledgement: only later activity of reputed
  members shortens the wait; a lone spammer still waits 24h
- revoke claws back the +1K even after settle (rule 1.b),
  plus 45% of the revoke weight from the author
    - revoked spam nets the spammer -450 per post
    - only never-revoked posts keep their earn
- revoke floor stays 1000 (`260831-min-vote.md`: burying
  costs more than speech)
- emission bound: 1K per epoch per member, epoch >= one
  action by half of the others

# Open

- two-pioneer chain: each action by the other opens the
  slot; alternating posts mint per post (cap-bounded)
- farming in isolation: x, y below 50% of the rest, so
  24h ceiling; epochs shrink as they grow
- 50% point and linear form inherited from rule 2
- linear scans in `find`/`nexthead`: index by member?
- docs: reps.md (ln 45-49, 108, 138), paper

# Paper (main.tex)

- 398 rule 1.b: "after 24h" -> "within 24h"; "once a day"
  -> "once per period"
- 638, 655 T3: consolidates within 24h, sooner with reputed
  activity; reward once per period
- 662: period shrinks with reputed activity after the last
  reward; keep "regulates emission"
- 932 chain time: "up to 24h"
- 1059 farming: "once per period, 24h in isolation"
- one phrase: members may pace posts to the period
- keep "consolidate"; "settle" is the 7-day window

# Won't do

- per-chain time scale (`time.full` per chain): replaced
  by the adaptive rule
- revoke at 500: weakens the censorship price
- slot advances by scaled period: period 0 in busy chains
- unbounded queue: per-post emission, delayed
- floor at 12h: keeps the backlog, blocks the conference
- ratio at record time: ignores later activity
