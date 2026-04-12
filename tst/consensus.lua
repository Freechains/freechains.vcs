-- 6a. recv conflict — local wins (loser = remote)
do
    print("==> Step 6a: recv conflict — local wins")

    TEST "A creates conflict-a chain + seeds shared.txt"
    exec(EXE_A .. " --now=9000 chains add conflict-a init " .. GEN_1)
    exec (
        EXE_A .. " --now=9100 chain conflict-a post inline 'seed\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B clones conflict-a"
    exec(EXE_B .. " chains add conflict-a clone " .. ROOT_A .. "/chains/conflict-a/")

    TEST "A appends alpha (earlier)"
    exec (
        EXE_A .. " --now=10000 chain conflict-a post inline 'alpha\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B appends beta (later)"
    exec (
        EXE_B .. " --now=11000 chain conflict-a post inline 'beta\n' --file shared.txt --sign " .. KEY1
    )

    TEST "A recvs from B (A wins)"
    exec (
        EXE_A .. " --now=12000 chain conflict-a sync recv " .. ROOT_B .. "/chains/conflict-a/"
    )

    TEST "A's shared.txt has alpha, not beta"
    local h = io.open(ROOT_A .. "/chains/conflict-a/shared.txt")
    local content = h:read("a")
    h:close()
    assert(content:match("alpha"), "alpha missing: " .. content)
    assert(not content:match("beta"), "beta should be discarded: " .. content)

    TEST "A's posts.lua has only the winning post"
    local posts = dofile(ROOT_A .. "/chains/conflict-a/.freechains/state/posts.lua")
    local n = 0
    for _ in pairs(posts) do n = n + 1 end
    -- seed + alpha, beta discarded
    assert(n == 2, "expected 2 posts (seed+alpha), got " .. n)
end

-- 6b. recv conflict — remote wins (loser = local)
do
    print("==> Step 6b: recv conflict — remote wins")

    TEST "A creates conflict-b chain + seeds shared.txt"
    exec(EXE_A .. " --now=9000 chains add conflict-b init " .. GEN_1)
    exec (
        EXE_A .. " --now=9100 chain conflict-b post inline 'seed\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B clones conflict-b"
    exec(EXE_B .. " chains add conflict-b clone " .. ROOT_A .. "/chains/conflict-b/")

    TEST "A appends alpha (later)"
    exec (
        EXE_A .. " --now=11000 chain conflict-b post inline 'alpha\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B appends beta (earlier)"
    exec (
        EXE_B .. " --now=10000 chain conflict-b post inline 'beta\n' --file shared.txt --sign " .. KEY1
    )

    TEST "A recvs from B (B wins, A's conflicting post discarded)"
    local out = exec (
        EXE_A .. " --now=12000 chain conflict-b sync recv " .. ROOT_B .. "/chains/conflict-b/"
    )
    assert(out:match "ERROR : content conflict\nvoided : %S+\n")

    TEST "A's shared.txt has beta, not alpha"
    local h = io.open(ROOT_A .. "/chains/conflict-b/shared.txt")
    local content = h:read("a")
    h:close()
    assert(content:match("beta"), "beta missing: " .. content)
    assert(not content:match("alpha"), "alpha should be discarded: " .. content)

    TEST "A's posts.lua has only the winning post"
    local posts = dofile(ROOT_A .. "/chains/conflict-b/.freechains/state/posts.lua")
    local n = 0
    for _ in pairs(posts) do n = n + 1 end
    assert(n == 2, "expected 2 posts (seed+beta), got " .. n)
end


