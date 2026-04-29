#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/sync/A/"
local ROOT_B = ROOT .. "/sync/B/"
local ROOT_X = ROOT .. "/sync/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"
local REPO_X = ROOT_X .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)
exec("mkdir -p " .. ROOT_X)

-- shared setup: A creates chain, B clones
exec(EXE_A .. " --now=1000 chains add test init file " .. GEN_1)
exec(EXE_B .. " chains add test clone " .. REPO_A)
-- A:  [state] G
-- B:  [state] G

local function head (repo)
    return exec("git -C " .. repo .. " rev-parse HEAD")
end

local function begs (repo)
    return exec (
        "git -C " .. repo .. " for-each-ref refs/begs/ --format='%(refname)'"
    )
end

local P1, BEG_K2, BEG_K3  -- captured in earlier steps, reused later

-- 1. recv basic
do
    print("==> Step 1: recv basic")

    TEST "A posts"
    P1 = exec(EXE_A .. " --now=2000 chain test post inline 'p1' --sign " .. KEY1)
    -- A:  G ── [post] P1 ── [state] S1
    -- B:  G

    TEST "B recvs from A"
    exec(EXE_B .. " chain test sync recv " .. REPO_A)
    -- A:  G ── P1 ── S1
    -- B:  G ── P1 ── S1

    TEST "heads equal"
    assert(head(REPO_A) == head(REPO_B))
end

-- 2. send basic
do
    print("==> Step 2: send basic")

    TEST "A posts"
    exec(EXE_A .. " --now=3000 chain test post inline 'p2' --sign " .. KEY1)
    -- A:  G ── P1 ── S1 ── [post] P2 ── [state] S2
    -- B:  G ── P1 ── S1

    TEST "A sends to B"
    exec(EXE_A .. " chain test sync send " .. REPO_B)
    -- A:  G ── P1 ── S1 ── P2 ── S2
    -- B:  G ── P1 ── S1 ── P2 ── S2

    TEST "heads equal"
    assert(head(REPO_A) == head(REPO_B))
end

-- 3. recv begs
do
    print("==> Step 3: recv begs")

    TEST "A creates a beg"
    BEG_K2 = exec (
        EXE_A .. " --now=4000 chain test post inline 'please' --beg --sign " .. KEY2
    )
    assert(#BEG_K2 == 40)
    assert(begs(REPO_A):match("beg%-" .. BEG_K2))
    -- A:  G ── P1 ── S1 ── P2 ── S2        refs/begs/beg-BEG -> BEG
    --                           └── [beg] BEG
    -- B:  G ── P1 ── S1 ── P2 ── S2

    TEST "B recvs from A"
    exec(EXE_B .. " chain test sync recv " .. REPO_A)
    -- A:  G ── P1 ── S1 ── P2 ── S2        refs/begs/beg-BEG -> BEG
    --                           └── [beg] BEG
    -- B:  G ── P1 ── S1 ── P2 ── S2        refs/begs/beg-BEG -> BEG
    --                           └── [beg] BEG

    TEST "B has the beg ref"
    assert(begs(REPO_B) == begs(REPO_A))
end

-- 4. send begs
do
    print("==> Step 4: send begs")

    TEST "A creates another beg"
    BEG_K3 = exec (
        EXE_A .. " --now=5000 chain test post inline 'help' --beg --sign " .. KEY3
    )
    assert(#BEG_K3 == 40)
    -- A:  G ── P1 ── S1 ── P2 ── S2        refs/begs/{BEG1, BEG2}
    --                           ├── BEG1
    --                           └── BEG2
    -- B:  G ── P1 ── S1 ── P2 ── S2        refs/begs/BEG1
    --                           └── BEG1

    TEST "A sends to B"
    exec(EXE_A .. " chain test sync send " .. REPO_B)
    -- A:  G ── P1 ── S1 ── P2 ── S2        refs/begs/{BEG1, BEG2}
    --                           ├── BEG1
    --                           └── BEG2
    -- B:  G ── P1 ── S1 ── P2 ── S2        refs/begs/{BEG1, BEG2}
    --                           ├── BEG1
    --                           └── BEG2

    TEST "B has both beg refs"
    assert(begs(REPO_B) == begs(REPO_A))
end

-- 5. beg prune via recv
do
    print("==> Step 5: beg prune via recv")

    TEST "A likes BEG_K2 (promote + prune ref on A)"
    local beg = BEG_K2
    exec (
        EXE_A .. " --now=6000 chain test like 1 post " .. beg .. " --sign " .. KEY1
    )
    assert(not begs(REPO_A):match(beg), "A's beg ref should be pruned")
    -- A:  G ── P1 ── S1 ── P2 ── S2 ── [like] L ── [state] S      refs/begs/{BEG2}
    --                           └── BEG2
    -- B:  G ── P1 ── S1 ── P2 ── S2                                refs/begs/{BEG1, BEG2}
    --                           ├── BEG1
    --                           └── BEG2

    TEST "B recvs from A"
    exec(EXE_B .. " chain test sync recv " .. REPO_A)
    -- A:  G ── P1 ── S1 ── P2 ── S2 ── L ── S      refs/begs/{BEG2}
    --                           └── BEG2
    -- B:  G ── P1 ── S1 ── P2 ── S2 ── L ── S      refs/begs/{BEG2}
    --                           └── BEG2

    TEST "B's beg ref also pruned"
    assert(not begs(REPO_B):match(beg), "B's beg ref should be pruned")
end

-- 7. malicious like (liker has 0 reps) -> rejected
do
    print("==> Step 7: malicious like rejected")

    TEST "X clones from B"
    exec(EXE_X .. " chains add test clone " .. REPO_B)

    TEST "X crafts a raw like signed by KEY3 (0 reps) targeting P1"
    exec("mkdir -p " .. REPO_X .. ".freechains/likes/")
    local f = io.open(REPO_X .. ".freechains/likes/like-bad.lua", "w")
    f:write('return { target="post", id="'..P1..'", number=1 }\n')
    f:close()
    local now = 7000
    local date = "GIT_AUTHOR_DATE=$(date -u -d @" .. now .. " --iso-8601=seconds) "
        .. "GIT_COMMITTER_DATE=$(date -u -d @" .. now .. " --iso-8601=seconds) "
    exec (
        ENV .. " git -C " .. REPO_X
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-bad.lua"
    )
    exec (
        date .. ENV .. " git -C " .. REPO_X
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
        .. " commit -S -m 'bad' --trailer 'Freechains: like'"
    )
    exec (
        date .. "git -C " .. REPO_X .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "X sends to B: rejected"
    local _, Q, err = exec (true,
        EXE_X .. " chain test sync send " .. REPO_B
    )
    assert(Q ~= 0, "send should fail")
    assert (
        err and err:find("insufficient reputation"),
        "expected reps error, got: " .. tostring(err)
    )
end

-- 8. beg prune via send
do
    print("==> Step 8: beg prune via send")

    TEST "A likes BEG_K3 (promote + prune ref on A)"
    exec (
        EXE_A .. " --now=8000 chain test like 1 post " .. BEG_K3 .. " --sign " .. KEY1
    )
    assert(not begs(REPO_A):match(BEG_K3), "A's beg ref should be pruned")
    -- A:  ... ── L_K2 ── S ── [like] L_K3 ── [state] S      refs/begs/{}
    -- B:  ... ── L_K2 ── S                                  refs/begs/{BEG_K3}
    --                              └── BEG_K3

    TEST "A sends to B"
    exec(EXE_A .. " chain test sync send " .. REPO_B)
    -- A:  ... ── L_K2 ── S ── L_K3 ── S      refs/begs/{}
    -- B:  ... ── L_K2 ── S ── L_K3 ── S      refs/begs/{}

    TEST "B's beg ref also pruned"
    assert(not begs(REPO_B):match(BEG_K3), "B's beg ref should be pruned")
end

print("<== ALL PASSED")
