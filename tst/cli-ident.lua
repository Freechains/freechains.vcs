#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-ident/"

exec(ENV_EXE .. " chains add cli-ident init " .. GEN_1)

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

-- KEY2 idents
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
    assert(out:match("refs/idents/ident%-" .. KEY2), "ident ref not found: " .. out)
end

print("<== ALL PASSED")
