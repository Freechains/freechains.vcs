v0.21 (xxx/xx)
--------------

Additions:

- `chains add`
    - `--dictator=<key>`
        - can always post and vote, and always wins forks
    - open chains:
        - no `--pioneer`, `--dictator`
        - anyone may post and vote, including unsigned
- `chain list tips`: the DAG tips, one per line
- `chain get metadata genesis`
    - chain info

Modifications:

- chain alias: `/chat` (was `'#chat'`)
- genesis: `dictators:` and `pioneers:` sections
- `chain get metadata`: output is a Lua table
- `daemon stop [--port]`: kills every holder of the port

Fixes:

- votes: minimum of 500 reps
- `daemon start` fails fast when the port is busy

v0.20 (aug/26)
--------------

First release of the Lua implementation over Git.
