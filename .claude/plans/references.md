# References: External Documentation

## Academic Papers

| Paper                        | Venue | Year | URL                                                                  | Topics                                      |
|------------------------------|-------|------|----------------------------------------------------------------------|---------------------------------------------|
| Freechains: Disseminação     | SBSeg | 2020 | http://www.ceu-lang.org/chico/papers/fc_sbseg20_pre.pdf              | Protocol overview, 3 chain types, rep basics |
| de Conteúdo P2P              |       |      |                                                                      |                                             |
| Peer-to-Peer Permissionless  | SBSeg | 2023 | https://sol.sbc.org.br/index.php/sbseg/article/download/27227/27043/ | Consensus, variable discount, block states, |
| Consensus via Reputation     |       |      |                                                                      | hard forks, Table 2 rep rules **(MAIN)**    |
| (preprint variant)           | —     | 2022 | http://ceu-lang.org/chico/papers/fc_xxx22_pre.pdf                    | Earlier version of the SBSeg 2023 paper     |

## Official Documentation (GitHub)

| Document       | URL                                                            | Topics                       |
|----------------|----------------------------------------------------------------|------------------------------|
| README (main)  | https://github.com/Freechains/README                           | Project overview, links      |
| Chains         | https://github.com/Freechains/README/blob/master/docs/chains.md | Chain types, topics, feeds |
| Blocks         | https://github.com/Freechains/README/blob/master/docs/blocks.md | Block structure, post states |
| Reputation     | https://github.com/Freechains/README/blob/master/docs/reps.md | Rules 1-4, economy, design   |
| Consensus      | https://github.com/Freechains/README/blob/master/docs/cons.md | Branch ordering, hard forks  |
| Commands       | https://github.com/Freechains/README/blob/master/docs/cmds.md | CLI reference                |
| Other systems  | https://github.com/Freechains/README/blob/master/docs/others.md | Comparison with alternatives |
| Join guide     | https://github.com/Freechains/README/blob/master/docs/join.md | Public chains, peers         |

## Source Code

| Repository            | URL                                              | Notes                    |
|-----------------------|--------------------------------------------------|--------------------------|
| Kotlin implementation | https://github.com/Freechains/freechains.kt/     | Reference implementation |
| Android dashboard     | https://github.com/Freechains/android-dashboard/  | Mobile UI                |

## Articles & Essays

| Title                                | URL                                                 | Topics                       |
|--------------------------------------|-----------------------------------------------------|------------------------------|
| Freechains and Ostrom's Principles   | https://fsantanna.github.io/Freechains/cpr.html     | Common-pool resources        |
| Freechains vs Tragedy of the Commons | https://fsantanna.github.io/Freechains/tragedy.html | Economy model, consolidation |

## Videos

| Title              | URL                                             |
|--------------------|-------------------------------------------------|
| Introduction (1/3) | https://www.youtube.com/watch?v=7_jM0lgWL2c     |
| Introduction (2/3) | https://www.youtube.com/watch?v=bL0yyeVz_xk     |
| Introduction (3/3) | https://www.youtube.com/watch?v=APlHK6YmmFw     |

## Community

| Resource         | URL                                                    |
|------------------|--------------------------------------------------------|
| Google Group     | https://groups.google.com/forum/#!forum/freechains     |
| Author's page    | https://fsantanna.github.io/                           |
| Author's Twitter | https://twitter.com/_fsantanna                         |

## Key Rules Quick Reference (SBSeg 2023, Table 2)

| Rule | Name     | Effect                 | Key detail                                                                    |
|------|----------|------------------------|-------------------------------------------------------------------------------|
| 1.a  | pioneers | +30 reps split equally | Bootstrap                                                                     |
| 1.b  | old post | +1 rep to author       | 24h to consolidate; 1 per day per author                                      |
| 2    | new post | -1 rep temporarily     | Discount 0-12h, proportional to subsequent reputed activity;                  |
|      |          |                        | 0 if >=50% total reps active after it; 12h if no activity                     |
| 3.a  | like     | -1 origin, +1 target   | Targets: post + author                                                        |
| 3.b  | dislike  | -1 origin, -1 target   | >=3 dislikes AND more dislikes than likes -> contents hidden                  |
| 4.a  | min      | need >=1 rep to post   | Sybil gate                                                                    |
| 4.b  | max      | capped at 30 reps      | Incentivizes spending                                                         |
| 4.c  | size     | <=128 KB per post      | DDoS prevention                                                               |

## Block States (SBSeg 2023, Figure 3)

```
start -> reps > 0 -> ACCEPTED <-> +/- reps
      -> reps = 0 -> BLOCKED  -> +1 like -> ACCEPTED
                                          -> REVOKED (no payload)
```

## Variable Discount Period (Rule 2, Key Formula)

From SBSeg 2023 paper, Table 2 observation:

> The discount period varies from 0 to 12 hours and is
> proportional to the sum of authors' reps in subsequent
> posts.
> It is 12 hours with no further activity.
> It is zero if further active authors concentrate at
> least 50% of the total reputation in the chain.

```
subsequent_reps = sum of reps of authors who posted after this post
total_reps      = total reputation in the chain
ratio           = subsequent_reps / total_reps

discount_hours  = 12 * max(0, 1 - ratio/0.5)
                = 12 * max(0, 1 - 2*ratio)

Examples:
    ratio = 0.0  -> 12h  (no activity)
    ratio = 0.25 ->  6h  (25% of reps active)
    ratio = 0.5  ->  0h  (50%+ of reps active)
```

## Consolidation (Rule 1.b)

After the discount period ends AND 24h have passed since
the author's previous consolidated post, the post
consolidates and grants +1 rep to the author.
Only 1 consolidated post per author per day counts.
