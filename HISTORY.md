v0.21 (xxx/xx)
--------------

Additions:

- dictators:
    - `--dictator=<key>`
    - can always post and vote, and always wins forks
- open chains:
    - no `--pioneer`, `--dictator`
    - anyone may post and vote, including unsigned

Modifications:

- chain alias: `/chat` (was `'#chat'`)
- genesis: `dictators:` and `pioneers:` sections

Fixes:

- votes: minimum of 500 reps

v0.20 (aug/26)
--------------

First release of the Lua implementation over Git.
