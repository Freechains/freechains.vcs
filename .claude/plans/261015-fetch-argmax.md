# Payload fetch: refspecs past the shell arg cap (26/10/15)

# Context

- found in 2606-sims `p2p/scale.sh`: clone of a 5k-post chain
  fails (ia-optim 5ebae95); clone at 1k already 14 s
- `exec` runs `io.popen(cmd)`: one `sh -c` string, capped at
  128 KB by Linux (MAX_ARG_STRLEN); past it `popen` returns nil:
  `common.lua:59: attempt to index a nil value (local 'h')`
- `err=false` does not help: the crash is before the exit code

# Cause

- ia-optim (`sync.lua:548`): payload fetch by explicit cids
  (260903-128KB, step 2), one refspec per post to fetch, about
  115 B each: breaks past ~1100 new posts (clone, big pull)
- main (`sync.lua:271`): one glob, plus one negative refspec per
  REVOKED post, 58 B each: breaks past ~2260 revoked posts
- other long command lines to check: `chains.lua` clone fetch,
  any `table.concat` of cids into `cmd`

# Fix

- refspecs through stdin: `git fetch --stdin <remote>` (git 2.43
  has it), negative refspecs too
- `exec` input: reuse the stdin path of `git_in` (state.lua) or
  a temp file
- check `popen` nil in `exec`: raise "bug found" with the cmd
  size, not a nil index

# Tests

- ia-optim `tst/bug-fetch-argmax.lua`: 1200 posts, B recvs all
  at once, C clones; fails at B recv
- main `tst/bug-fetch-argmax.lua`: 2400 posts self-revoked, B
  recvs, C clones

# Status

- [x] both failing tests written; [x] ia-optim fails
- [ ] main fails: run voided (/tmp/freechains wiped mid-run by
  another `make test`); rerun alone (~22 min)
- [ ] fix main: same (`sync.lua:263` glob + revoked excludes via
  stdin, `exec` nil popen), test commented in Makefile; running
  suites + test
- [x] fix ia-optim: `sync.lua` payload refspecs via `fetch
  --stdin` (temp file); `exec` raises on nil popen; test passes
  (3 min), commented out in Makefile; 47/47 suites, guide.sh
- [ ] clone cost vs size (14 s at 1k, > 75 s at 5k): separate
