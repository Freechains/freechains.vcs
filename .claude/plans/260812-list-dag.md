# 260812-list-dag

- rewrite `list dag` rendering from scratch
- standalone `dag.lua` first (no git, no chain): DAG table in,
  diagram out
- old formatting rules dropped (groups, averages, annotations)

# Rules

- 1: each node appears at its DEPTH line
    - depth(root) = 0; depth(n) = 1 + max(depth(ups))
- 2: nodes at the same depth share the line, side by side
    - columns are POSITION-based, parents centered:
        - all columns EVEN (STEP multiple of 4, joins rounded):
          edge midpoints stay exact, no rounding skew
        - root: middle column
        - single up: inherit the up's column
        - fork: children spread symmetrically around the up
        - join: midpoint of the ups' columns
    - within a depth, insertion order decides left-to-right
- 3: edges connect nodes properly
    - glyph above the CHILD, on the edge line, at the midpoint
    - `|` same column, `\` parent to the left, `/` to the right
    - parent in an UPPER level (depth gap > 1): `^` at the
      midpoint + 3-char parent hint on the parent's side
      (`abc^` when up-left, `^abc` when up-right)
- 4: alternate 1 node line, 1 edge line
- 5: revoked ids render as `~id~` (optional `revoked` set)

# DAG format

- the pair `(order, ups)`: `render(order, ups)`
    - `order`: array of ids, insertion (consensus) order;
      earlier entries always render above later ones; also the
      left-right tie-break within a depth
    - `ups`: map id -> array of ids it links back to (`backs`);
      a root maps to `{}`
- why the pair: it is BOTH ends at once
    - from the chain: `order` = `G.order`, `ups[aid]` = action
      file `backs` (identity conversion)
    - into the renderer: depth needs `ups` by id, iteration
      needs the array; `downs`/`depth`/`col` are derived
- `{ id, up1, ... }` entry lists rejected: a third shape that
  needs slicing into this one anyway

# A. diamond table

```lua
local order = { "A", "B", "C", "D" }
local ups   = {
    A = {},
    B = { "A" },
    C = { "A" },
    D = { "B", "C" },
}
```

# B. diamond diagram

```
   A
  / \
 B   C
  \ /
   D
```

# C. our example table

- the X consensus DAG from the README (fork after the like on Bob)

```lua
local order = {
    "560a55c",      -- like: alice -> bob
    "c7d8e9f",      -- 'A great post!'
    "d8e9f0a",      -- like: alice -> beg
    "a1b2c3d",      -- 'Alice was here'
    "e6d7626",      -- like: bob -> charlie
    "a9b0c1d",      -- like: charlie -> hello
    "b0c1d2e",      -- dislike: bob -> here
    "f4e5d6c",      -- 'Charlie was here'
}
local ups = {
    ["560a55c"] = {},
    ["c7d8e9f"] = { "560a55c" },
    ["d8e9f0a"] = { "c7d8e9f", "560a55c" },
    ["a1b2c3d"] = { "d8e9f0a" },
    ["e6d7626"] = { "560a55c" },
    ["a9b0c1d"] = { "e6d7626" },
    ["b0c1d2e"] = { "a9b0c1d" },
    ["f4e5d6c"] = { "b0c1d2e" },
}
```

# D. our example diagram

- depths: 0=560a55c | 1=c7d8e9f,e6d7626 | 2=d8e9f0a,a9b0c1d |
  3=a1b2c3d,b0c1d2e | 4=f4e5d6c

```
      560a55c
     /       \
c7d8e9f     e6d7626
    |          |
d8e9f0a     a9b0c1d
    |          |
a1b2c3d     b0c1d2e
               |
            f4e5d6c
```

- f4e5d6c inherits b0c1d2e's column (single up)
- the fork spreads c7d8e9f/e6d7626 around 560a55c

# Step 1 DONE: dag.lua (repo root)

- `render(order, ups)` as specified; both examples inside
- actual output deviates from the D sketch, for the better:
  `d8e9f0a` is a JOIN, so the midpoint rule places it BETWEEN
  its ups -- and the long edge `560a55c -> d8e9f0a` renders
  as a visible `/` instead of merging:

```
      560a55c
      /     \
c7d8e9f     e6d7626
    \  /       |
   d8e9f0a  a9b0c1d
      |        |
   a1b2c3d  b0c1d2e
               |
            f4e5d6c
```

- long-edge merge now only happens when parent and child land
  on the SAME column (a join never does, for both ups)
- not handled yet: column collisions between unrelated
  branches; edge crossings
- ADDED after review: `^` glyph for upper-level parents (the
  old a/b/c options die: the edge is always drawn, `^` says
  "from further up"); `revoked` set -> `~id~` labels
- ADDED examples: full guide (root to moderation: fork, beg
  join, `day 1` joining both tips, abandoned post absent,
  2 revoked) and minimal revoked chain -- all four render

# RESOLVED: long edges (depth gap > 1) -> `^` glyph

- historical options below (superseded)

# old options: long edges

- `560a55c -> d8e9f0a` skips depth 1
- options:
    - a: glyph at landing only, direction from the parent lane;
      here it merges with the `|` from c7d8e9f (edge invisible)
    - b: as (a), plus `(^560a55c)` annotation under the child
      when the landing glyph merged
    - c: route pass-through `|` in free cells across lines
      (complex, collides with occupied lanes)
- recommendation: a (simplest; the DAG stays readable, `get
  metadata` shows exact backs); b if the loss matters

# Alternative: tree-style (dag2.lua)

- unix `tree` DFS with prefix strings, ~40 lines
- every edge appears: expansion under the FIRST parent in
  consensus order, `id (shared)` stub under later parents
- joins do not converge visually: stubs are matched by name
- CAVEAT: width grows with chain LENGTH (one indent level per
  action) -- freechains histories are mostly linear, so a real
  chain drifts off-screen fast (full-guide tail already ~70
  cols after 18 actions)
- possible deviation: do not indent single-child continuations
  (only forks nest) -- keeps DFS simplicity, bounds width by
  fork breadth
- DECIDE: grid (dag.lua) vs tree (dag2.lua, with or without
  the no-indent deviation)

# Ugly cases (5 added to dag.lua)

- tri: 3-way fork + 3-up join -- CLEAN
- late beg: beg admitted after the chain advanced -- CLEAN
  (`BEG^` hint, join of skewed depths)
- nested: forks inside forks -- BROKEN: inner spreads collide,
  A2 overwritten by B1 (node LOST)
- criss-cross: two joins sharing both parents -- BROKEN: same
  midpoint, same depth, J1 LOST
- roots: join lands under an unrelated root -- misleading
  (reads as its child), nothing lost
- FIX DONE: columns assigned depth by depth, then per-row
  sweep (sort by col, tie by insertion; shift right to keep
  SEP = even(W+4)); collisions now slant edges instead of
  losing nodes; all 9 examples render complete
- roots stacking illusion left as is (cosmetic)
- files moved to `tst/dag.lua`, `tst/dag2.lua`

# Step 2 DONE: ported into list.lua

- `ARGS.dag` branch replaced wholesale (old group-based
  renderer gone, TODO note with it)
- inputs: `order` = `G.order`, `ups[aid]` = action file
  `backs`, labels = `aid:sub(1,7)`, revoked wrapped `~~`
- FIX found by the guide: a SAME-COLUMN long edge (beg like
  whose second back is straight up) collided with the `|`,
  glyph survival depended on sorted-aid order -- now the hint
  shifts one cell right: `|^560` (both visible, deterministic)
- cli-list + list-dag-roots expectations rewritten to the new
  layouts (derived columns matched the impl on first run)
- README dags retranscribed (basics, sync, begging, consensus
  A/B/X); X shows a real two-column fork now
- suite 38/38; guide.sh end to end
- `tst/dag.lua` kept as the reference implementation

# Next steps

- move plan to done/ if the shapes are final
