# Plan: check-errors

Test coverage for all error paths in `src/`.

## Untested Errors

| #  | Error Message                                | Source File        | Line     | Status  |
|----|----------------------------------------------|--------------------|----------|---------|
| 4  | sync replay: unsigned like (empty `%GF`)     | `chain/sync.lua`   | 25-26    | TEST ADDED (err-sign.lua), needs code fix |
| 12 | `chain post : copy failed: <path>`           | `chain/post.lua`   | 32       | PENDING |
| 13 | `chain reps : post requires a hash`          | `chain/reps.lua`   | 13       | PENDING |
| 14 | `chain reps : author requires a pubkey`      | `chain/reps.lua`   | 29       | PENDING |
| 15 | `chain reps : invalid target : <target>`     | `chain/reps.lua`   | 44       | PENDING |
| 16 | `chain sync : fetch failed`                  | `chain/sync.lua`   | 87       | PENDING |
| 17 | `chain sync : push failed`                   | `chain/sync.lua`   | 80       | PENDING |
| 18 | `chain sync : invalid remote : <err>`        | `chain/sync.lua`   | 119      | PENDING |
| 19 | `invalid like : <hash>` (replay)             | `chain/sync.lua`   | 38,45,49 | PENDING |
| 20 | `chains add : alias already exists: <alias>` | `chains.lua`       | 38       | PENDING |
| 22 | `chains add : git init failed`               | `chains.lua`       | 60       | PENDING |
| 23 | `chains add : copy genesis failed`           | `chains.lua`       | 71       | PENDING |
| 24 | `chains add : chain already exists: <hash>`  | `chains.lua`       | 88       | PENDING |
| 25 | `chains add : git clone failed`              | `chains.lua`       | 100      | PENDING |
| 28 | sync replay: valid sig, key missing locally  | `chain/sync.lua`   | 21,64    | PENDING (solved by SSH signing — key embedded in commit) |
| 29 | sync replay: bad/forged sig as unsigned      | `chain/sync.lua`   | 21,64    | PENDING (needs SSH migration + verify in replay) |

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

- #27 (like with bad GPG key): reputation check in `apply()` catches
  the bad key before `git commit -S` runs, so the GPG failure is
  never reached. Test passes as `insufficient reputation`.
- #26 (post with bad GPG key): DONE. Added `'stdout'` + error msg
  to exec call in `chain/post.lua`. Test passes.
- Items 16, 17, 22, 23, 25 are git/IO failures -- harder to test.
- Items 4, 13, 14, 15, 20 are simple validation errors -- easy to
  test via CLI.
