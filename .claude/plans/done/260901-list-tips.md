# chain list tips

- New subcommand: `chain <alias> list tips`
- Prints the DAG tips, one cid per line
- Tips: blocks in `G.order` that are ups of no other block
- Covers v0.8 `chain heads` (see `260820-cli.md`)
- Name `tips` over `heads`: git idiom, no `HEAD` clash

# Changes (DONE)

- `src/freechains.lua`
    - add `tips = {}` to the `list` ARGS table
    - add `cmd.chain.list.tips._` command
- `src/freechains/chain/list.lua`
    - update header comment with `tips`
    - new `ARGS.tips` branch
        - `ACTION.backs { GIT.deref("HEAD") }`
        - no `G.order`: same primitive post uses
          for the backs of a new action
- `tst/cli-list.lua`
    - tips after P1, P2 (linear)
    - tips on fork (two, sorted)
    - tips after like-join (single)
- `doc/cli.md`
    - document `list tips`
- `.claude/plans/260820-cli.md`
    - mark `chain heads` item as covered

# Decisions

- output sorted by cid
- bare cids, no `~~` wrapping for revoked
