#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-ident/"

exec(ENV_EXE .. " chains add cli-ident init " .. GEN_1)

-- ERRORS: no --sign, invalid key, invalid bio, invalid pvt, pioneer
do
    -- ident with pioneer key (already in main state) must fail
    do
        TEST "ident-pioneer-fails"
        local _,Q,err = exec (true,
            ENV_EXE .. " chain cli-ident ident --sign " .. KEY
        )
        assert (
            Q~=0 and err=="ERROR : chain ident : already registered"
            , "should fail: " .. tostring(err)
        )
    end

    -- ident without --sign must fail
    do
        TEST "ident-without-sign-fails"
        local _,Q,err = exec (true,
            ENV_EXE .. " chain cli-ident ident"
        )

        local msg =
[[Usage: freechains chain ident [-h] --sign <sign> [--why <why>] [<bio>]

Error: missing option '--sign'
]]

        assert (
            Q~=0 and err==msg
            , "should fail: " .. tostring(err)
        )
    end

    -- ident with invalid key must fail
    do
        TEST "ident-invalid-key-fails"
        local _,Q,err = exec (true,
            ENV_EXE .. " chain cli-ident ident --sign bad-key"
        )
        assert (
            Q~=0 and err=="ERROR : chain ident : invalid sign key"
            , "should fail: " .. tostring(err)
        )
    end

    -- ident with invalid bio must fail
    do
        TEST "ident-invalid-bio-fails"
        local _,Q,err = exec (true,
            ENV_EXE .. " chain cli-ident ident /no.md --sign " .. KEY2
        )
        assert (
            Q~=0 and err=="ERROR : chain ident : invalid bio : /no.md"
            , "should fail: " .. tostring(err)
        )
    end

    -- ident with pubkey-only key (no private) must fail
    do
        TEST "ident-no-private-key-fails"
        local _,Q,err = exec (true,
            ENV_EXE .. " chain cli-ident ident --sign " .. KEY4
        )
        assert (
            Q~=0 and err=="ERROR : chain ident : invalid sign key"
            , "should fail: " .. tostring(err)
        )
    end
end

-- KEY2 ident, no bio
do
    local REF = "refs/idents/ident-" .. KEY2
    local IDENT
    do
        TEST "ident-succeeds"
        local out,Q = exec (
            ENV_EXE .. " chain cli-ident ident --sign " .. KEY2
        )
        assert(Q == 0, "exit code: " .. tostring(Q))
        assert(#out == 40, "hash length: " .. #out)
        IDENT = out
    end

    do
        TEST "ident-on-ref"
        local out = exec (
            "git -C " .. DIR .. " for-each-ref refs/idents/ --format='%(refname)'"
        )
        assert (
            out == "refs/idents/ident-" .. KEY2
            , "ident ref not found: " .. out
        )
    end

    do
        TEST "ident-trailer"
        local trailer = exec (
            "git -C " .. DIR .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. REF .. "~1"
        )
        trailer = trailer:match("(%S+)") or ""
        assert(trailer == "ident", "trailer: " .. trailer)
    end

    do
        TEST "ident-no-bio"
        local out = exec (
            "git -C " .. DIR .. " ls-tree -r " .. REF .. " .freechains/idents/"
        )
        assert(not out:match(KEY2 .. "%.md"), "bio should not exist: " .. out)
    end

    do
        TEST "ident-state-author-added"
        local src = exec (
            "git -C " .. DIR .. " show " .. REF .. ":.freechains/state/authors.lua"
        )
        local A = load(src)()
        assert(A[KEY2], "KEY2 not in authors: " .. src)
        assert(A[KEY2].reps == 0, "expected reps=0, got: " .. tostring(A[KEY2].reps))
    end

    do
        TEST "ident-already-registered-fails"
        local _,Q,err = exec (true,
            ENV_EXE .. " chain cli-ident ident --sign " .. KEY2
        )
        assert (
            Q~=0 and err=="ERROR : chain ident : already registered"
            , "should fail: " .. tostring(err)
        )
    end
end

-- KEY3 ident, with bio
do
    local bio = TMP .. "/bio.md"
    local f = io.open(bio, "w")
    f:write("# About\n\nHello, I am test3.\n")
    f:close()

    do
        TEST "ident-with-bio-succeeds"
        local _,Q = exec (
            ENV_EXE .. " chain cli-ident ident " .. bio .. " --sign " .. KEY3
        )
        assert(Q == 0, "exit code: " .. tostring(Q))
    end

    local REF3 = "refs/idents/ident-" .. KEY3

    do
        TEST "ident-bio-in-ref"
        local out = exec (
            "git -C " .. DIR .. " ls-tree -r " .. REF3 .. " .freechains/idents/"
        )
        assert(out:match(KEY3 .. "%.md"), "bio not found in ref: " .. out)
    end

    do
        TEST "ident-bio-content"
        local content = exec (
            "git -C " .. DIR .. " show " .. REF3 .. ":.freechains/idents/" .. KEY3 .. ".md"
        )
        assert(content:match("Hello, I am test3"), "bio content mismatch: " .. content)
    end
end

-- KEY (pioneer) approves KEY2 via like author
do
    local REF = "refs/idents/ident-" .. KEY2
    local HEAD = exec("git -C " .. DIR .. " rev-parse HEAD")

    local LIKE
    do
        TEST "like-author-succeeds"
        local out, Q = exec (
            ENV_EXE .. " chain cli-ident like 1 author " .. KEY2 .. " --sign " .. KEY
        )
        assert(Q == 0, "exit code: " .. tostring(Q))
        LIKE = out
    end

    do
        TEST "like-author-merges"
        local head = exec("git -C " .. DIR .. " rev-parse HEAD")
        assert(head ~= HEAD, "HEAD should advance after merge")
    end

    do
        TEST "like-author-key2-on-main"
        local A = dofile(DIR .. ".freechains/state/authors.lua")
        assert(A[KEY2], "KEY2 not in main authors.lua")
    end

    do
        TEST "like-author-asc-on-main"
        local f = io.open(DIR .. ".freechains/keys/" .. KEY2 .. ".asc")
        assert(f, ".asc file not in main keyring")
        f:close()
    end

    do
        TEST "like-author-ref-removed"
        local _, code = exec(true,
            "git -C " .. DIR .. " rev-parse --verify " .. REF
        )
        assert(code ~= 0, "ident ref should be removed")
    end
end

print("<== ALL PASSED")
