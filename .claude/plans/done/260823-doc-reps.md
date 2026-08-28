# doc/reps.md : image adjustments

`doc/reps.md` was adapted from old `README/docs/reps.md`
(text updated to vcs semantics). The two images were
copied as-is and still show the old kt-era rules:

- `doc/general.png`
- `doc/rules.png`

No editable source exists anywhere in the Freechains
GitHub org (checked all repos for `.dia`/`.fodp`/`.odp`/
`.odg`/`.svg`; only `block.dia`, `chain.dia`, and simul
topology diagrams exist; the tables are not in
`uff-22.fodp` either). Both must be redrawn from the
bitmaps.

## rules.png

| Cell | Old              | New                                 |
|------|------------------|-------------------------------------|
| 1.a  | +30 reps         | +50000 reps split among pioneers    |
| 1.b  | +1 rep           | +1000 reps to author                |
| 2    | -1 rep           | -500 reps temporarily               |
| 3.a  | -1/+1 rep        | -n origin, +n targets minus 10% tax |
| 3.b  | -1/-1 rep        | same rescale (-n both sides)        |
| 4.a  | at least +1 rep  | must afford full cost (post >= 500, vote >= n) |
| 4.b  | at most +30 reps | at most 50000 reps                  |
| 4.c  | 128 Kb           | unchanged                           |

Observations column:

- [2]   0-12h discount text: still correct, keep
- [3.a] like splits half to post, half to author;
        author-like delivers whole (after tax)
- [3.b] REMOVE "at least 3 dislikes and more dislikes
        than likes hides contents" and "revoke own
        posts with a single dislike"
        -> revocation is a separate explicit vote
        (`revoke`/`unrevoke`), reps-weighted; the
        author's self-revoke is free and absolute
- [4.a] optionally mention `--beg`

Other:

- typo: "Tranfer" -> "Transfer"
- optionally add a Revocation operation row
  (rule 3.b split out of Transfer), matching the
  new doc text

## general.png

- typo: "Tranfer" -> "Transfer"
- optionally add 4th row:
  Revocation | Revokes hide abusive payloads |
  Moderate abuse without central authority

## TODO

- [ ] redraw rules.png with new values
- [ ] redraw general.png (typo + revocation row)
- [ ] keep an editable source in doc/ this time
      (e.g. .dia / .fodp next to the .png)
