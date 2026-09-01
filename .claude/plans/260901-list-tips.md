# chain list tips

- New subcommand: `chain <alias> list tips`
- Prints the DAG tips, one cid per line
- Tips: blocks in `G.order` that are ups of no other block
- Covers v0.8 `chain heads` (see `260820-cli.md`)
- Name `tips` over `heads`: git idiom, no `HEAD` clash

# Changes

- `src/freechains.lua`
    - add `tips = {}` to the `list` ARGS table
    - add `cmd.chain.list.tips._` command
- `src/freechains/chain/list.lua`
    - update header comment with `tips`
    - new `elseif ARGS.tips` branch
        - mark every up of every block
        - print unmarked ids in `G.order` order
    - reuse `ACTION.backs(GIT.parents(h))` as in dag
- `.claude/plans/cli.md`
    - document `list tips`
- `.claude/plans/260820-cli.md`
    - mark `chain heads` item as covered

# Decisions

- output sorted by cid
- bare cids, no `~~` wrapping for revoked
