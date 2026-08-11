# 280808-redesign

- sources: `trash/b803-260802-redesign.md`, `trash/b807-260807-redesign.md`

# PENDING

- small, decided but not written:
    - D: `freechains gc` (stage 1): drop orphaned payload refs
      + `git gc --prune=now`, `--dry-run`, size report
    - E: `freechains gc` (stage 2, needs S1): prune
      `.git/states/` outside the settled window, once a
      missing snapshot can be recomputed
- the sync phase (own section below): S1 recv, S2 clone,
  S3 send/hook, S4 cleanups, B6 receive validation, E3's
  sync half (removal trigger at the replay settle, the
  `^refs/payloads/<removed>` refspec)
    - knock-on: 25 early-exited tests, `guide.sh` stops at
      the clone
- open questions:
    - how replay recognizes a SIGNED `--beg` (today
      `beg or (key == nil)`)
    - after B6: `kind` from `act.action`, `env` sheds
      `sign`/`time`
- plan hygiene: `260802-remove-blob.md` says "absent but not
  revoked -> payload unavailable"; `get` now ASSERTS instead
  (an honest peer holds the payload of every post it holds
  non-revoked). Fix that line when sync lands
- spec backlog lives in `reps.md`: Rule 5 file-op costs,
  revocation state (3.b), 128 KB limit, bilateral-sync and
  tie-breaker tests

# Done (already on main)

- `chain/consensus.lua` extracted from sync.lua
    - `octopus`, `consensus`, `commit`, `replay` (climb/meet)
- FF special-casing removed from recv
    - unified into diverge path
    - post-replay hardfork check
    - state probe after final ref update
- snap writes landed then REVERTED (563a745)
    - only `git_config` -> `git_init` refactor kept
- `tmp/` -> `.git/` (allowed_signers scratch)
- fixes: clone drops pending begs, clock skew (pinned `GIT_*_DATE`)
- `tst/trash/bug-forged-state.lua`: 4 holes proven red, parked
- NOT present: snapshots, backfill, `.git/index.lua`,
  `actions/<aid>.lua`; trailers + 4-file `state/` tree still live

# Aid ladder (local-only; suite green after each; before sync)

- ground rule: 260803-redesign is reference only, no code reuse
- A0 DONE: sign read from `.pub` file BEFORE commit
    - `ssh.pub.key(path)` = first two fields of `<path>.pub`
    - `ssh.pubkey` -> `ssh.pub.commit` (others' commits:
      get, consensus, verify) — reference naming adopted
    - post/like `T.sign` = pub.key, read early; missing/invalid
      `.pub` fails early, same error message
- v2 reorder: CLI flips BEFORE internals (v1 A2-then-A4 built a
  throwaway translation layer in list/reps/get)
- traps (learned in v1):
    - aid->cid walk must take the OLDEST `-m` match (merges also
      list a beg's file as added)
    - never `return assert(v, msg)`: returns BOTH values
- B1 DONE: action files in the commit (additive)
    - `ACTION` in common.lua: `write(T)` mints aid pre-commit,
      `aid(cid)` via diff-tree, `backs(ps)` sorted aids
    - post `{action, backs, sign, time, blob}`;
      vote `{action, backs, sign, time, post|author, n}`
    - get `commit_file` excludes `.freechains/actions`
    - CLI, G, trailers unchanged
- B2 DONE: CLI speaks aids; internals still commit-keyed
    - argparse: get/destroy `<hash>` -> `<id>`, `:target("aid")`
      (code reads `ARGS.aid`); like/revoke keep `ARGS.id`
      (aid OR pubkey, target-dependent)
    - post/like print aid; `refs/begs/beg-<aid>`
    - `ACTION.cid(aid)` added (nil on unknown, oldest -m match)
    - entry translations: like `tid`, get/destroy `cid`,
      reps `entry()`; prints translate cid->aid (list order/
      revokes/dag labels, reps posts/revokes, destroy report,
      get metadata backs)
    - get metadata: field `hash` kept, value = aid
    - tests: `CID`/`AID` helpers; probes translated in
      cli-sign, cli-like, cli-begs, cli-destroy
- B3 DONE: G keyed by aid
    - `apply` takes `T.aid` (`T.cid` stays for PEAKS);
      `T.post` is an aid; posts/order hold aids
    - translations die: like `tid`, get/reps lookups,
      list order/revokes/dag maps
    - get backs + dag ups from the action file
      (`cat-file blob <aid>`) — no commit walk in readers
    - like keeps the fail-fast `ACTION.cid` existence check
    - tests: cli-begs snapshot posts[] back to direct aids
- METADATA DONE: `get metadata` = the action file
    - one `cat-file blob <aid>`; time/why/sign/vote reads die;
      unused `ssh` require dropped
    - output shape = the file: `action`, flat `post|author`/`n`,
      `blob` (not filename), `sign` absent when unsigned
    - `why` gone from metadata; at payload eviction a vote's
      payload BECOMES its why (commit messages go empty;
      `--why` leaves post; why-text deletable like any payload)
    - trap again: `io.write(exec{...})` prints (out, code) ->
      parenthesize multi-return calls in argument position
- B3b DONE: apply BEFORE commit
    - `ACTION.write` split: `pre(T)` mints aid (tmp in `.git/`,
      worktree untouched), `pos(aid)` places + stages on accept
    - `apply` takes `T.parents` (resolved cids: HEAD, +ref on
      beg like); `T.cid` gone
    - writer order: payload -> pre -> apply -> add + pos ->
      commit; reject removes the payload file (+ merge --abort
      on a beg like); reset rollbacks die
    - the commit exists only for ACCEPTED actions
    - trap (3rd time): `{ exec{...} }` captures (out, code)
- VOTE FILES DONE: `.freechains/likes|revokes/` die
    - a vote commit = its action file, nothing else
    - like.lua: payload write, `file` var, add, reject-remove
      all gone; skel loses both dirs
    - genesis tree = actions/.gitkeep + genesis.lua + random
    - tests: like-payload-file -> action-file-only diff assert
- B4 DEMOTED: probably unnecessary — revisit after eviction
    - `ACTION.cid` callers shrank to get + destroy; E1 removes
      get's; one walk on rare `destroy` is acceptable
    - if revived: variant B (write-through) was the decision
- E1 DONE: payload leaves the tree
    - post payload -> loose blob (`hash-object -w`), anchored
      `refs/payloads/tmp-<rand>` over the mint window, renamed
      to `refs/payloads/<aid>` after apply accepts
    - commit diff = the action file, for EVERY action
    - `get payload` = `cat-file blob <T.blob>`; commit_file dies
    - get membership via `G.order` scan: ACTION.cid out of get
      (destroy is its last caller)
    - filename machinery dies: no worktree payload, no
      "file already exists", collisions impossible; worktree
      root is EMPTY of user files
    - `--file <path>` absolutized (git -C chdirs first)
    - destroyed actions: payload REF lingers until E3; `get`
      already refuses via membership
    - tests: cli-post file/inline sections rewritten (payload
      via get, anchor ref, empty worktree, no collisions);
      cli-destroy payload probes -> get-based
- E2 DONE: votes gain payloads; why unification
    - `--why` = the vote's OPTIONAL payload: staged, DRY-hashed
      into the action file's `blob`, written + anchored at
      `refs/payloads/<aid>` post-accept (same scheme as post)
    - `get payload` keyed by `T.blob` presence: posts always,
      votes with `--why`; else empty output (uniform with an
      empty post payload; "no payload" error dropped)
    - `--why` leaves post's CLI; commit messages are TRULY
      empty (`--allow-empty-message -m ''`): no user text in
      undeletable objects, no placeholder either
    - cost accepted: `git log` no longer informative
    - tests: cli-post --why section -> reject + empty-msg;
      cli-like why-as-payload + empty-payload; cli-get vote
      payloads -> empty output
    - parked: err-post/err-like forgery gsubs on
      "(empty message)" match nothing now -> new tamper
      vector needed at sync phase
- NO DEBT -> moved to `done/260809-reps.md` (cost-quantized gates
  + reps parameter review; must ship before sync/release)
- REPS UNITS DONE: one currency — CLI speaks internal units
  (landed BEFORE no-debt: order flipped, holes stay open
  until NO DEBT — must ship before sync/release)
    - drop the ext/int seam: `reps` prints raw (15450), `like N`
      takes raw (450); `ext()` + its lying ceil die
    - `C.reps.unit` field deleted (nothing reads it; the local
      `unit` var stays as the scale of cost/max constants)
    - rationale: exact integers end to end; the x1000 scale
      exists for tax/split integrality and is now visible
    - tests: all vote magnitudes x1000; expectations recomputed
      to exact internals (ceil had lied: "16" was 15450,
      post "1" was 450, "0 1" channels was 0/1000)
    - README transcript + guide.sh renumbered (Charlie's "5"
      was ceil(4500) -> 4500)
- RENAME DONE: `destroy` -> `abandon`
    - mechanism is local (only your repo changes) but the
      meaning is global: resolving a hard fork by abandoning
      your sub-history to become compatible with the settled
      one (and incompatible with the abandoned one)
    - CLI command, destroy.lua -> abandon.lua, error strings,
      rockspec module, tests (cli-destroy -> cli-abandon)
    - also README + guide.sh (executable `chain abandon` call)
    - tst/trash/ untouched (parked, pre-redesign)
- E3: deletion becomes real
    - SOURCE: `260802-remove-blob.md` already settled the
      design; it predates aids (keys refs by blob sha, we key
      by aid -- refcounting works either way)
    - REVOKE IS THE TRIGGER: a post whose final sums say
      REVOKED loses its bytes. What the source decouples is
      the *display hide* (Phase 1) from the *removal* (Phase
      2), NOT revocation from deletion
    - removal (sync phase): act ONCE on the final sums after a
      full replay, never mid-walk (a sum dips negative from
      ordering alone); mechanics `update-ref -d` then
      `git gc --prune=now`
    - restore needs no step: a post that recomputes
      non-negative is simply back in the set the next sync's
      refspec asks for -- which is why lifting a revoke is
      gated on having the bytes NOW (below)
    - non-resurrection (sync phase): negative refspec
      `^refs/payloads/<removed>` per removed post, else every
      fetch re-imports the deleted bytes
    - GATED UNREVOKE: `unrevoke` -- and a `like` that would
      actually flip `is_revoked` to false -- must materialize
      the payload FIRST, else
      `ERROR : chain unrevoke : blob unavailable`
        - sources: local object store, a peer's
          `refs/payloads/<aid>`, or the user's own copy via
          `--file` (hash-object it, accept ONLY if it matches
          the action file's `blob`; content-addressing makes
          the check free and forgery-proof)
        - a self-like that cannot lift an author revoke is
          NOT gated
    - read path: revoked -> `chain get : revoked post`; absent
      but not revoked -> `chain get : payload unavailable`;
      never a raw traceback
    - LOCAL SLICE DONE: abandon drops `refs/payloads/<aid>` for
      every abandoned action (blob unreachable, next `gc
      --prune` reclaims); `get payload` reports
      `payload unavailable` instead of crashing on a missing
      blob; `unrevoke` is gated -- refuses with
      `blob unavailable`, accepts `--file` only when its
      hash-object matches the action file's `blob`, else
      `blob mismatch`
        - tests: cli-abandon (ref gone / kept), cli-revoke
          "Gated unrevoke" (refused, wrong file, right file)
        - removal fires LOCALLY on the crossing: a local vote
          settles immediately (no replay walk, so no
          intermediate dip), so a vote that takes a post INTO
          revoked drops `refs/payloads/<aid>` right there, and
          one that takes it OUT re-anchors
        - the decisions read the REAL sums after `apply` (an
          earlier version simulated the axis and duplicated
          `apply`'s routing)
        - errors name the verb typed (`unrevoke`, `dislike`),
          not the collapsed kind
        - the beg merge moved past every check, so
          `merge --abort` disappeared: nothing is written
          before the last possible refusal
        - what remains sync-phase is the trigger for histories
          replayed from a peer, not the local one
    - A DONE: `--file` is VERIFIED whenever given, not only when
      the blob is missing (it was silently ignored) -- the caller
      cannot see the store, so a redundant fallback is fine and a
      wrong one is an error
        - check split from the write: plain `hash-object` to
          compare, `-w` only on the missing branch, so a
          mismatching file no longer lands a junk blob
        - errors unchanged (`invalid path`, `blob mismatch`,
          `expected --file`); new case in cli-revoke
    - C DONE: revoke floor -- a vote on the axis weighs at least
      `C.reps.revoke` (1000); zero-crossing threshold unchanged,
      author channel still absolute and still free
        - floor is on `kind=='revoke'` only (revoke AND unrevoke):
          a like/dislike carries none, so the axis only ever moves
          negative in units
        - `invalid number : expects at least 1000`, refused in
          rules.lua (so replay refuses it too)
        - every existing call already used 1000; docs updated
          (reps.md 3.b, README, cli-revoke header)
    - STILL SYNC-PHASE: the removal trigger (act once on final
      sums after a full replay) and the non-resurrection
      refspec `^refs/payloads/<removed>`
- S6a DONE: drop `.freechains/` + skel dies (unblocked by E1)
    - tree root = `actions/` (sharded `ab/<aid>.lua`),
      `genesis.lua`, `random`; FC constant dies
    - `ACTION.path(aid)` helper; `aid()` pathspec dropped,
      pattern `actions/%x+/(%x+)%.lua`; `pos` mkdirs the bucket
    - skel deleted: `chains add` mkdirs `actions/` + writes
      `.gitkeep` + `random` + `genesis.lua` directly, `add .`
    - `write(G)` deleted (sync-only; its dirs are gone)
    - `random` STAYS (protocol: genesis uniqueness seed)
    - tests: paths updated (tests.lua CID, cli-post, cli-like,
      cli-chains); cli-post empty-worktree assert lists the
      three internals
- B5 DONE: trailers die on the write path
    - post/like/genesis commits carry NO trailer: the envelope
      is tree + parents + signature only
    - classification structural: action <=> adds its action
      file (`ACTION.aid(cid) ~= nil`); kind = the file's
      `action` field (get.lua)
    - `ACTION.backs` rec: aid-or-recurse; trailer dispatch +
      "invalid trailer" error die
    - destroy: resolution IS the proof-of-action (kind check
      dropped); report skips non-actions gracefully
    - `trailer()` kept, marked sync-only (dies at sync phase)
    - tests: trailer probes -> action-field asserts (cli-like,
      cli-chains "no trailer", cli-now by %at only); TRAILER
      helper deleted
- B6: receive-side validation -> deferred to sync phase

# Q DONE: revocation targets payloads, not posts

- FOUND while reviewing E2: a vote's `--why` is user-authored
  text with its own payload blob, but `revoke <vote>` failed
  with "invalid target : post not found" -- `G.posts` held
  only posts, so votes had no revoke axis. The rule predated
  `--why` being a payload
- the promise it closes: moderation says any abusive text can
  be hidden and removed, wherever it was written
  (`260802-remove-blob.md`: "no user bytes in the DAG")
- `G.posts` -> `G.actions`: ONE registry, an `action` field
  ('post' | 'like' | 'revoke') mirroring the action file's
    - a vote registers itself at the end of its own `apply`
    - snapshot facet renamed with it (`serial(G)` is generic)
- a vote is SCORED like a post (`reps`), so voting on one
  credits or drains its signer -- same tax and split
    - what a vote lacks is `maturity`: both time scans key on
      it, so a vote receives reps and never earns them (no 12h
      refund, no 24h consolidation)
    - no farming loop: a like is a taxed transfer, so liking
      each other's votes loses 10% a round
    - `reps posts` therefore lists votes too -- hence the
      rename to `reps actions` below
- the author channel is the target's signer either way: "its
  author forgot it" == "its signer forgot their why"
- VOCABULARY (landed with Q, before B6 freezes the wire): the
  word `post` meant "not an author" in three places, all of
  which now say what they mean
    - CLI keyword: `like|dislike <n> action <aid>` (was `post`);
      `revoke|unrevoke` still take no keyword
    - action file field: `aid` (was `post`) -- `action` was
      unavailable, it names the file's own kind; the pair
      `aid` | `author` still tells the two targets apart BY
      FIELD NAME, no discriminator needed
    - `reps action <id>` / `reps actions` (was `post`/`posts`),
      now that a vote is scored; `reps revoke(s)` unchanged
    - `like.lua` normalizes the CLI word to the FIELD name at
      the top, so the rest of the file is unchanged
    - `expects 'post' or 'author'` -> `expects 'action' or
      'author'`; `revoke` alone -> `expects 'action'`
    - trap: `act.aid` (the TARGET) vs `env.aid` (the action's
      OWN id) are different tables -- noted at `apply`
- `revoke` still refuses an author target
- `invalid target : post not found` -> `action not found`
- `chain get : revoked post` -> `revoked payload` (a vote is
  not a post; the message is about the bytes)
- LIFT gate skips an action with no `blob` (a vote without
  `--why` has nothing to materialize)
- a revoked vote still counts for reps/consensus: only the
  bytes hide, the action stands (as with a post)
- settled by the score: like/dislike on a vote are meaningful
  (they weigh its why), so no target restriction was added
- tests: the two "votes are not posts" refusals became a
  section where a why is read, revoked (signer drained 450),
  self-revoked (free, author channel) and scored; unknown-aid
  refusal added
- left alone: `chain get : unknown post` (an unknown aid is
  not a post either, but that string predates Q)

# Next steps (sync phase)

- goal: re-green the 25 early-exited tests, one by one
- S1: recv derives state from actions, snaps adopted tips
    - G_oct = snapshot at octopus (recompute region on miss)
    - replay commit(): no state commits arrive; mode check =
      action adds only; PEAK on remote commits via snapshots
      written during replay
    - drop tree reads: G_fst, O_snd, hardfork order (sync.lua)
    - drop tree writes: write(G), merge state commit, probe
- S2: clone = base case of recv
    - replay genesis -> tip, snapshot every commit
    - validate or delete the clone (eager at chains add)
- S3: send/pre-receive hook on new protocol; make install
- S4: cleanups after sync lands
    - delete write(G); 'state' cases in backs()/trailer walkers
    - genesis trailer rethink; consensus.lua state-path checks
- later (from b803): payload eviction, action files (aid),
  commit<->id index, prune/GC of snapshots

# apply's T (why not the action table)

- apply's input = the COMMIT-derived view of an action; the
  action table = the wire object; neither contains the other
    - `aid`: the file's own hash — cannot be in the file
    - `parents`: cids (PEAKS reads cid-keyed snapshots); the
      file stores `backs` (aids)
    - `beg`: local circumstance, recomputed per site (writer:
      refs/begs/ probe; replay: maturity=='beg')
    - replay takes sign/time from the ENVELOPE (verified
      signature, commit %at), NEVER from the file: the
      explicit T whitelists the trusted fields by construction
- candidate at S1 (pending decision): `apply(G, act, env)`
    - `act` = the action file table as-is (content: n,
      post/author; action replaces the kind arg; sign/time
      readable once PINNED, see below)
    - `env` = {aid, parents} (+beg): NON-OVERLAPPING,
      envelope-derived; the two names make provenance visible;
      writers stop duplicating fields into a second table
    - PRECONDITION: recv validation pins the file to the
      envelope (signature verified against the file's `sign`,
      `time` == commit %at) BEFORE apply — until that check
      exists, the whitelist-T is the safer shape
    - vote `beg` derivable INSIDE apply (like + n>0 +
      maturity=='beg'): env shrinks to {aid, parents} for
      votes; post `beg` needs a story first — how does replay
      recognize a signed --beg? (file field? action='beg'?)

# Ladder (local-only; all local tests pass after each step; DONE)

- state `G` = `{ authors, actions, order, now }` (4 facets)
    - snapshot = `serial(G)` in `.git/states/<cid>.lua`
- L1 DONE: snaps after local actions — dual write
    - `snap(G, is_ref, rev)` in common.lua
    - genesis (`chains add`, direct write), post, like
      (beg: snapped before the reset)
    - `mkdir .git/states/` in `git_init`
    - sync untouched; nothing reads snapshots yet
- L2 DONE: local reads of snaps
    - `STATE(rev)` in common.lua: snapshot at rev, no fallback
      (missing snapshot = "bug found")
    - `PEAK` = `STATE(hash).now`
    - init.lua startup `G` = `STATE("HEAD")`
    - like-on-beg entry = `STATE(ref).actions[id]`
    - no backcompat: old chains unsupported; sync recv leaves
      unsnapped tips -> sync tests may fail (accepted)
    - 25 tests early-exit before first clone/recv dependence:
      marker "280808 : EARLY EXIT"; local prefix still asserted;
      repl-remote-* stop their git daemons before exiting
    - Makefile: cli-get-merge moved after cli-begs (first
      sync-dependent test); suite green end to end
    - destroy unchanged: reset still restores tree state (L3)
- L3 DONE: remove state commits + tree state from local writers
    - possible w/o aid redesign: snapshot written AFTER commit,
      cid known -> no cycle
    - one commit per action; beg 2 -> 1; destroy `beg~2` -> `beg~1`
    - like beg merge: no `-X ours`; beg ref = the post itself
      (like.lua order entry: `ref~1` -> `ref`)
    - genesis: tree = genesis.lua + random + likes/ + revokes/;
      skel loses state/ + .gitattributes; pioneers() returns
      the authors table (snapshot-only); no now.lua write
    - snapshots now keyed by ACTION commits (tips)
    - `write(G)` (tree state) kept: sync-only, dies at sync phase
    - tests: HEAD~1 -> HEAD anatomy; STATE(dir) helper in
      tests.lua (snapshot at HEAD) replaces state/ dofiles;
      state-commit TESTs removed (get/destroy); repl counts -1;
      err-like exit moved up (recv dies at G_oct tree read now)
    - suite green end to end
- dropped: backfill walk (only needed for commits we did not
  create: sync interiors, clone) — deferred to sync phase

# What leaves commits

- state (`state.lua` / `state/`): no longer committed at all (S15)
- state commits themselves: action + state join into one commit (S9)
- payloads (post content, like `--why`): out of the tree (S10)
- trailers (`Freechains:` kind): classification derived from tree (S11a)
- commit messages: truly empty (no placeholder), no user text
- `.freechains/` prefix, `.gitattributes`, `.gitignore`, skel

# What enters commits

- one `actions/<aid>.lua` per action:
    - `{action, backs (aids), sign, time, blob, post/author, n}`
- tree = `actions/` (sharded `ab/`) + `genesis.lua` + `random`
- merges: pure topology, empty diff
- genesis: no actions

# What enters local state

- per-commit snapshots of whole `G` -> `.git/states/<cid>.lua`
    - written at tips + replay
    - backfill walk fills interiors, clone, old chains
- commit<->aid index -> `.git/index.lua` (`{tip, a2c, c2a}`)
- payload blobs anchored by `refs/payloads/<aid>` (never in tree)
- `allowed_signers` scratch -> `.git/`

# What leaves local state

- remote/committed state: never read again
    - `G_oct`, `PEAK`, worktree `dofile`, destroy, like-on-beg
      all switch to snapshots
- verification machinery never built:
    - no `state_link`, no verify walk
    - no `refs/freechains/verified` frontier
    - no write+diff probe
- GC: snapshots below the settled hardfork window die (S15.3)
- prune:
    - below-cut snapshots die
    - prune-point snapshot rekeyed to the new orphan root
    - `.git/index.lua` deleted, rebuilt lazily
- worktree `tmp/` gone (moved into `.git/`)
