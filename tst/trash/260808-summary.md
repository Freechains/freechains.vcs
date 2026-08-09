# Trash index (260808)

Main tests not wired into the Makefile, moved out of tst/.

Branch test variants (b802/b803/b806 prefixed) were dropped
entirely: every one shared its name with a test still alive in
tst/ — same name, same purpose, main's version wins.

# Files

- `bug-forged-state.lua` — ACTIVE bug test, 4 scenarios
  (diverge tip, interior stealthy, merge side, clone), all RED
  on main. NOTE: under the snapshot design its expectations
  flip: forgery becomes INERT (sync/clone succeed, reps stay
  derived), not refused — rewrite before restoring (see
  plans/trash b807-260807-redesign.md)
- `url.lua` — chat-alias test, not in the Makefile

# Still in tst/ (untouched)

- all 37 Makefile tests, `tests.lua` harness,
  `genesis-[0-4].lua` fixtures
