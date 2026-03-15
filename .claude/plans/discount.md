# Plan: Variable Discount Engine (Rule 2) — COMPLETED

## Context

Test `tst/cli-time.lua` line 23 fails.
It expects that posting P2 immediately refunds P1's cost
(discount=0 because author is active, ratio=1.0).
Currently, the code only deducts post cost without any
discount/refund logic.

## Critical Files

| File                | Action | Purpose                        |
|---------------------|--------|--------------------------------|
| `src/common.lua`    | edit   | serial() handles nested tables |
| `src/constants.lua` | edit   | Uncomment `time.discount`      |
| `src/freechains`    | edit   | Add discount engine            |
| `tst/cli-reps.lua`  | edit   | Update expected value 27→29    |

## Step 1: Enhance `serial()` in `src/common.lua`

Add local helper `val(v)` to serialize values:
- number → `tostring(v)`
- string → `'"' .. v .. '"'`
- table → `"{ k1=v1, k2=v2 }"` (keys sorted)

Detect arrays (`#t > 0` and all keys 1..#t exist):
- Array → `val(v),` per entry (no key)
- Map → `["k"] = val(v),` per entry (existing)

```lua
local function val (v)
    if type(v) == "number" then
        return tostring(v)
    elseif type(v) == "string" then
        return '"' .. v .. '"'
    elseif type(v) == "table" then
        local parts = {}
        for k, v2 in pairs(v) do
            parts[#parts+1] = k .. "=" .. val(v2)
        end
        table.sort(parts)
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
end

function serial (t)
    local n = #t
    local is_array = n > 0
    if is_array then
        for i = 1, n do
            if t[i] == nil then
                is_array = false; break
            end
        end
    end
    local lines = {}
    if is_array then
        for i = 1, n do
            lines[#lines+1] = "    " .. val(t[i]) .. ","
        end
    else
        local keys = {}
        for k in pairs(t) do
            keys[#keys+1] = k
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            lines[#lines+1] = '    ["' .. k .. '"] = '
                .. val(t[k]) .. ","
        end
    end
    return "return {\n"
        .. table.concat(lines, "\n") .. "\n}\n"
end
```

## Step 2: Uncomment `time.discount` in `src/constants.lua`

```lua
    time = {
        tolerance     = 1*h,
        discount      = 12*h,       -- uncomment
        ...
    },
```

## Step 3: Add discount engine to `src/freechains`

Inside the "update reps on post/like" `do` block
(lines 365–407), restructure to:

1. Load `time/posts.lua` alongside `reps/authors.lua`
2. **Before** post/like effects: scan discount
3. **After** post/like effects: add entry if signed post
4. Write both files

### Discount scan logic

For each entry with `state == "00-12"`:

```lua
local subs = {}
-- entries created after this one
for j, other in ipairs(tposts) do
    if j > i then
        subs[other.author] = true
    end
end
-- current author counts as activity
if args.sign then
    subs[args.sign] = true
end

local sreps = 0
for a in pairs(subs) do
    sreps = sreps + math.max(0, authors[a] or 0)
end
local treps = 0
for _, v in pairs(authors) do
    treps = treps + math.max(0, v)
end

local ratio = treps > 0 and sreps / treps or 0
local discount = C.time.discount
    * math.max(0, 1 - 2*ratio)

if NOW >= entry.time + discount then
    authors[entry.author] =
        (authors[entry.author] or 0) + C.reps.cost
    entry.state = "12-24"
end
```

### New entry on signed post

After the post cost deduction:

```lua
tposts[#tposts+1] = {
    author = args.sign,
    time   = NOW,
    state  = "00-12",
}
```

### Write time/posts.lua

```lua
files = files .. " .freechains/time/posts.lua"
write(tposts, REPO .. "/.freechains/time/posts.lua")
```

## Step 4: Update `tst/cli-reps.lua` line 67

With discount, 3 posts by the same pioneer yield 29
(each previous post refunded by the next):

```
P1: 30 → 29 (cost)
P2: refund P1 → 30 → 29 (cost)
P3: refund P2 → 30 → 29 (cost)
```

Change: `assert(out == "27"` → `assert(out == "29"`

## Trace: cli-time test

```
--now=0, 1 pioneer, KEY=30000

P1: discount scan: tposts empty → skip
    cost: KEY=30000-1000=29000
    add tposts[1]={author=KEY, time=0, state="00-12"}

P2: discount scan: tposts[1] state="00-12"
    subs={KEY} (current author)
    sreps=29000, treps=29000, ratio=1.0
    discount=43200*max(0,1-2)=0
    NOW(0) >= 0+0 → refund: KEY=30000, state="12-24"
    cost: KEY=30000-1000=29000
    add tposts[2]={author=KEY, time=0, state="00-12"}

reps author KEY → 29 ✓ (line 23)
```

## Verification — ALL PASSED

```
make test T=cli-time   ✓
make test T=cli-reps   ✓
make test T=cli-like   ✓
make test T=cli-now    ✓
```

## Changes vs Plan

- `serial()`: simplified beyond plan — unified `val()` handles
  all types (boolean, number, string, table), no array/map
  distinction, always uses explicit keys `[k]=`
- `tst/cli-reps.lua`: also fixed `reps-target-disliked`
  assertion (`n < 14` → `n == 14`) to account for discount
  refunds
