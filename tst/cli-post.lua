#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/#cli-post/"

exec {
    cmd = ENV_EXE .. " chains add '#cli-post' init --pioneer=" .. KEY1,
}

-- POST FILE
do
    print("==> freechains chain post file")

    local P1
    do
        TEST "post file success"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-post' post file hello.txt --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")
        P1 = out
    end

    do
        TEST "payload retrievable (out of the tree)"
        local v = exec {
            cmd = ENV_EXE .. " chain '#cli-post' get payload " .. P1,
        }
        assert(v == "Hello World!", "content: " .. v)
    end

    do
        TEST "payload anchored on refs/payloads/<aid>"
        local ref = exec {
            cmd = "git -C " .. DIR .. " rev-parse refs/payloads/" .. P1,
        }
        assert(#ref == 40, "anchor missing: " .. ref)
    end

    do
        TEST "no payload file in the tree"
        local _, code = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR .. " cat-file -e HEAD:hello.txt",
        }
        assert(code ~= 0, "hello.txt should not exist in the tree")
    end

    do
        TEST "genesis still in tree"
        local _, code = exec {
            cmd = "git -C " .. DIR .. " cat-file -e HEAD:genesis.lua",
        }
        assert(code == 0, "genesis.lua missing")
    end

    do
        TEST "same name never collides"
        local tmp = TMP .. "/hello.txt"
        local f = io.open(tmp, "w")
        f:write("collision attempt\n")
        f:close()
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-post' post file " .. tmp .. " --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local v2 = exec {
            cmd = ENV_EXE .. " chain '#cli-post' get payload " .. out,
        }
        assert(v2 == "collision attempt", "content: " .. v2)
        local v1 = exec {
            cmd = ENV_EXE .. " chain '#cli-post' get payload " .. P1,
        }
        assert(v1 == "Hello World!", "first payload should be intact: " .. v1)
    end
end

-- POST INLINE
do
    print("==> freechains chain post inline")

    do
        TEST "inline payload retrievable"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-post' post inline 'Quick note' --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        local v = exec {
            cmd = ENV_EXE .. " chain '#cli-post' get payload " .. out,
        }
        assert(v == "Quick note", "content: " .. v)
    end

    do
        TEST "tree carries no user files"
        local files = exec { trim=false,
            cmd = "git -C " .. DIR .. " ls-tree --name-only HEAD",
        }
        assert(files == "actions\ngenesis.lua\nrandom\n",
            "expected internals only: " .. files)
    end
end

-- POST --why: gone -- a post's payload IS its text, and no user
-- text may live in the (undeletable) commit message
do
    print("==> freechains chain post --why")

    do
        TEST "post rejects --why"
        local _, code = exec { err=false, stderr=false,
            cmd = ENV_EXE .. " chain '#cli-post' post inline 'some text' --sign " .. KEY1 .. " --why 'reason'",
        }
        assert(code ~= 0, "--why should be rejected")
    end

    do
        TEST "post commit message is always empty"
        exec {
            cmd = ENV_EXE .. " chain '#cli-post' post inline 'no reason' --sign " .. KEY1,
        }
        local msg = exec {
            cmd = "git -C " .. DIR .. " log -1 --format=%s HEAD",
        }
        assert(msg == "", "commit message should be empty: " .. msg)
    end
end

-- POST errors
do
    print("==> freechains chain post errors")

    do
        TEST "post to nonexistent chain fails"
        local tmp = TMP .. "/hello.txt"
        FAIL {
            cmd = ENV_EXE .. " chain '#nochain' post file " .. tmp .. " --sign " .. KEY1,
            err = "ERROR : chain #nochain : not found",
        }
    end

    do
        TEST "post inline rejects --file"
        local err = FAIL {
            cmd = ENV_EXE .. " chain '#cli-post' post inline 'x' --file /tmp/x --sign " .. KEY1,
        }
        assert(err:match("Error: unknown option '%-%-file'"), "should reject --file")
    end

    do
        TEST "post file copy failed"
        -- the error carries cp's own detail (>>> ... <<<)
        local err = FAIL {
            cmd = ENV_EXE .. " chain '#cli-post' post file /tmp/nonexistent-file.txt --sign " .. KEY1,
        }
        assert(err == [[
ERROR : chain post : invalid path
>>>
cp: cannot stat '/tmp/nonexistent-file.txt': No such file or directory
<<<
]])
    end
end

print("<== ALL PASSED")
