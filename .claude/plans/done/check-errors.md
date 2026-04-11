# Plan: check-errors

Test coverage for all error paths in `src/`.

## Untested Errors

| #  | Error Message                                | Source File        | Line     | Status  |
|----|----------------------------------------------|--------------------|----------|---------|
| 4  | sync replay: unsigned like (`ssh.pubkey` nil) | `chain/sync.lua`   | 35-37    | DONE (`err-like.lua` tests this) |
| 12 | `chain post : invalid path`                  | `chain/post.lua`   | 22-24    | DONE (`cli-post.lua`) |
| 13 | `chain reps : post requires a hash`          | `chain/reps.lua`   | 13       | DONE (`cli-reps.lua`) |
| 14 | `chain reps : author requires a pubkey`      | `chain/reps.lua`   | 29       | DONE (`cli-reps.lua`) |
| 15 | `chain reps : invalid target : <target>`     | `chain/reps.lua`   | 44       | DONE (`cli-reps.lua`) |
| 16 | `chain sync : invalid fetch`                 | `chain/sync.lua`   | 94       | DONE (`err-post.lua`) |
| 17 | `chain sync : push failed`                   | `chain/sync.lua`   | 88       | SKIPPED (dead code — `send` not implemented) |
| 18 | `chain sync : invalid remote : <err>`        | `chain/sync.lua`   | —        | REMOVED (error no longer exists in code) |
| 19 | `invalid like` replay variants               | `chain/sync.lua`   | 38-65    | DONE (`err-like.lua`: all replay paths + forged sig) |
| 20 | `chains add : alias already exists`          | `chains.lua`       | 38       | DONE (`cli-chains.lua`) |
| 22 | `chains add : init failed`                   | `chains.lua`       | 61-64    | DONE (`cli-chains.lua` — `--root /dev/null`) |
| 23 | `chains add : invalid genesis`               | `chains.lua`       | 42-56    | DONE (`cli-chains.lua`) |
| 24 | `chains add : clone failed` (dup hash)       | `chains.lua`       | 113-117  | DONE (`cli-chains.lua` — clone existing chain) |
| 25 | `chains add : clone failed` (bad URL)        | `chains.lua`       | 105-108  | DONE (`cli-chains.lua`) |
| 28 | sync replay: valid sig, key missing locally  | `chain/sync.lua`   | —        | RESOLVED (SSH embeds key in commit — no local keyring needed) |
| 29 | sync replay: bad/forged sig as unsigned      | `chain/sync.lua`   | 27       | DONE (`err-post.lua` tests forged signature rejection) |

## Already Tested (reference)

| #  | Error Message                                             | Test File       |
|----|-----------------------------------------------------------|-----------------|
| 26 | `chain post : invalid sign key`                           | `cli-sign.lua`  |
| 27 | `chain like : insufficient reputation` (bad key, rep gate)| `cli-like.lua`  |
| 1  | `chain post : too big time difference`                    | `cli-now.lua`   |
| 2  | `chain like : too big time difference`                    | `cli-now.lua`   |
| 3  | `chain post : insufficient reputation`                    | `cli-reps.lua`  |
| 5  | `chain like : invalid target : expects 'post' or 'author'` | `cli-like.lua` |
| 6  | `chain like : invalid target : post not found`            | `cli-like.lua`  |
| 7  | `chain like : insufficient reputation`                    | `cli-begs.lua`  |
| 8  | `chain <alias> : not found`                               | `cli-post.lua`  |
| 9  | `chain like : requires --sign`                            | `cli-like.lua`  |
| 10 | `chain post : --beg error : author has sufficient reputation` | `cli-reps.lua` |
| 11 | `chain post : requires --sign or --beg`                   | `cli-sign.lua`  |
| 21 | `chains add : file must return a table`                   | `cli-chains.lua`|
| 26r| `chains rem : not found: <alias>`                         | `cli-chains.lua`|
| 27r| `expected positive integer : got '<s>'`                   | `cli-like.lua`  |

## Notes

- #27 (like with bad sign key): the SSH commit fails before
  `apply()` runs. Test passes as `invalid sign key`.
- #26 (post with bad sign key): DONE. Added `'stdout'` + error msg
  to exec call in `chain/post.lua`. Test passes.
- #4: DONE. `err-like.lua` tests unsigned like rejection.
- #19: DONE. `err-like.lua` covers all replay like paths
  (unsigned, missing payload, bad lua ×2, bad target, post
  not found, insufficient reps, old time, fractional num,
  zero num, forged signature).
- #28: RESOLVED. SSH signing embeds the full public key in
  the commit signature — no local keyring lookup needed.
- #29: DONE. `ssh.verify()` now called in replay.
  `err-post.lua` tests forged signature rejection.
- Items 13, 14, 15, 20: DONE. All tested via CLI.
  Also removed `"TODO : TEST : "` prefix from reps.lua.
- Items 12, 16, 22, 23, 24, 25: DONE. Added `'stdout'`
  to silence stderr leak in several `exec` calls.
  #22 tested via `--root /dev/null` trick.
  #23 switched `dofile` → `loadfile` + format check.
  #24 switched clone `mv` → `os.rename` + error.
- Item 17: SKIPPED. `send` command is dead code.
