# 260812-list-dag

- rewrite `list dag` rendering from scratch
- standalone `dag.lua` first (no git, no chain): DAG table in,
  diagram out
- old formatting rules dropped (groups, averages, annotations)

# Rules

- 1: each node appears at its DEPTH line
    - depth(root) = 0; depth(n) = 1 + max(depth(ups))
- 2: nodes at the same depth share the line, side by side
    - lane = insertion order within the depth
    - fixed lane width (labels centered per lane)
- 3: edges connect nodes properly
    - glyph above the CHILD, on the edge line
    - `|` same lane, `\` parent to the left, `/` to the right
- 4: alternate 1 node line, 1 edge line

# DAG format

- array in insertion (consensus) order
- each entry: `{ id, up1, up2, ... }`

# A. diamond table

```lua
local DAG = {
    { "A" },
    { "B", "A" },
    { "C", "A" },
    { "D", "B", "C" },
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
local DAG = {
    { "560a55c" },                          -- like: alice -> bob
    { "c7d8e9f", "560a55c" },               -- 'A great post!'
    { "d8e9f0a", "c7d8e9f", "560a55c" },    -- like: alice -> beg
    { "a1b2c3d", "d8e9f0a" },               -- 'Alice was here'
    { "e6d7626", "560a55c" },               -- like: bob -> charlie
    { "a9b0c1d", "e6d7626" },               -- like: charlie -> hello
    { "b0c1d2e", "a9b0c1d" },               -- dislike: bob -> here
    { "f4e5d6c", "b0c1d2e" },               -- 'Charlie was here'
}
```

# D. our example diagram

- depths: 0=560a55c | 1=c7d8e9f,e6d7626 | 2=d8e9f0a,a9b0c1d |
  3=a1b2c3d,b0c1d2e | 4=f4e5d6c

```
560a55c
   |     \
c7d8e9f    e6d7626
   |          |
d8e9f0a    a9b0c1d
   |          |
a1b2c3d    b0c1d2e
        /
f4e5d6c
```

# Open: long edges (depth gap > 1)

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

# Next steps

- 0: confirm A-D shapes and the long-edge option
- 1: `dag.lua` standalone: table + render() + the two examples
- 2: port into `list.lua` (`backs` from action files; revoked
  as `~aid~`)
- 3: update cli-list, list-dag-roots expectations; README dags
