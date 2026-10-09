# Hub hook: shell injection via `url=`

# Problem

- a `--hub` runs the sender's `url=` push option through a shell
    - hooks/pre-receive ln 40-45: `sync recv '<url>'`, single
      quotes, no escaping: a quote ends the quoting
- the hook is not the only splice: `URL()` output goes UNQUOTED
  into git commands
    - sync.lua ln 80 (push), ln 93 and 271 (fetch)
    - chains.lua ln 335 (clone fetch)
    - so quoting the hook alone still runs `recv <url>` into an
      unquoted `git fetch <url>`
- option injection: a url starting with `-` reaches git as an
  option, e.g. `--upload-pack=<cmd>` runs a command
- impact: any peer allowed to `send` to a hub runs commands as the
  hub's user; locally, any caller of recv/send/clone with a crafted
  url
- found by reading the code, not reproduced

# Design

- one validator in `URL()` (common.lua ln 160), so every caller
  gets it
    - allowed chars only: letters, digits, `- . _ ~ / : # @ +`
    - must not start with `-`
    - else `ERROR : <command> : invalid url`
- hook: validate `url` with the same pattern before running recv
    - `ERROR : chain sync : invalid url`, exit 1
    - keep the single quotes (defense in depth)
- push `-o 'url=...'` (sync.lua ln 79): the sender's own
  `freechains.url`, validated by the same pattern

# Files

- src/freechains/common.lua: `URL()` validator
- src/freechains/hooks/pre-receive: validation before recv
- src/freechains/chain/sync.lua: own url check on send
- doc/cli.md: allowed url characters

# Won't do

- `ext::` transport: git refuses it by default
  (`protocol.ext.allow = never`)
- hub url policy, real push for `send`: TODO.md

# Open

- local paths with spaces become invalid (already broken today:
  unquoted)
