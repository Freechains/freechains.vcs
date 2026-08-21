require "freechains.common"

TMP   = "/tmp/freechains/"
ROOT  = TMP .. "/root/"
EXE   = "../src/freechains.lua --root " .. ROOT

SSH     = exec {
    cmd = "realpath ssh/",
} .. "/"
KEY1    = SSH .. "key1"
KEY2    = SSH .. "key2"
KEY3    = SSH .. "key3"
KEY4    = SSH .. "key4"
PUB1    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY1 .. ".pub",
}
PUB2    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY2 .. ".pub",
}
PUB3    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY3 .. ".pub",
}
PUB4    = exec {
    cmd = "awk '{print $1\" \"$2}' " .. KEY4 .. ".pub",
}
ENV     = ""
ENV_EXE = EXE

-- pioneer flags: GEN_N holds the first N keys
GEN_0   = ""
GEN_1   = "--pioneer='" .. PUB1 .. "'"
GEN_2   = GEN_1 .. " --pioneer='" .. PUB2 .. "'"
GEN_3   = GEN_2 .. " --pioneer='" .. PUB3 .. "'"
GEN_4   = GEN_3 .. " --pioneer='" .. PUB4 .. "'"

function TEST (name)
    print("  - " .. name .. "... ")
end

-- aid == cid: identity, kept for the callers' vocabulary
-- (asserts the commit exists in `dir`)
function CID (dir, aid)
    local ok = exec { err=false, stderr=false,
        cmd = "git -C " .. dir .. " cat-file -e " .. aid,
    }
    assert(ok, "no commit: " .. aid)
    return aid
end

-- the genesis table of the chain at `dir`: the genesis commit's
-- MESSAGE (body after the header block)
function GENESIS (dir)
    local src = exec { trim=false,
        cmd = "git -C " .. dir .. " cat-file commit refs/genesis",
    }
    return load(src:match("\n\n(.*)$"))()
end

-- repo-equality probe: trees are always empty (actions live in
-- messages), so HEAD's cid IS the whole chain (git's Merkle) --
-- stronger than the tree diff this helper used to return
function TREE (dir)
    return (exec {
        cmd = "git -C " .. dir .. " rev-parse HEAD",
    })
end

-- craft a raw git commit on the bare chain repo `dir`: message
-- `msg` (the action; nil = merge-like empty) over the EMPTY tree,
-- with optional ssh `sign` key. `files` (path -> content) builds a
-- NON-empty tree instead, to exercise the smuggling check.
-- Returns the new cid; moves HEAD
function COMMIT (dir, t)
    t = t or {}
    local tree
    if t.files then
        exec {
            cmd = "git -C " .. dir .. " read-tree --empty",
        }
        for path, content in pairs(t.files) do
            local tmp = dir .. "/craft-tmp"
            local f = io.open(tmp, "w")
            f:write(content)
            f:close()
            local blob = exec {
                cmd = "git -C " .. dir .. " hash-object -w " .. tmp,
            }
            os.remove(tmp)
            exec {
                cmd = "git -C " .. dir .. " update-index --add --cacheinfo " ..
                    "100644," .. blob .. "," .. path,
            }
        end
        tree = exec {
            cmd = "git -C " .. dir .. " write-tree",
        }
    else
        tree = exec {
            cmd = "git -C " .. dir .. " hash-object -t tree /dev/null",
        }
    end
    local msg = dir .. "/craft-msg"
    do
        local f = io.open(msg, "w")
        f:write(t.msg or "")
        f:close()
    end
    local sig = t.sign and
        (" -c user.signingkey=" .. t.sign .. " -c gpg.format=ssh") or ""
    local cid = exec {
        cmd = ENV .. " git -C " .. dir .. sig .. " commit-tree" ..
            (t.sign and " -S" or "") .. " -p HEAD " .. tree ..
            " < " .. msg,
    }
    os.remove(msg)
    exec {
        cmd = "git -C " .. dir .. " update-ref HEAD " .. cid,
    }
    return cid
end

-- raw-git merge on the bare repo `dir`: FF when possible, else
-- merge-tree + commit-tree, as `git merge` would
function MERGE (dir, other)
    local ok = exec { err=false, stderr=false,
        cmd = "git -C " .. dir .. " merge-base --is-ancestor HEAD " .. other,
    }
    if ok then
        local cid = exec {
            cmd = "git -C " .. dir .. " rev-parse " .. other,
        }
        exec {
            cmd = "git -C " .. dir .. " update-ref HEAD " .. cid,
        }
        return cid
    end
    local tree = exec {
        cmd = "git -C " .. dir .. " hash-object -t tree /dev/null",
    }
    local cid = exec {
        cmd = "git -C " .. dir .. " commit-tree " .. tree ..
            " -p HEAD -p " .. other .. " < /dev/null",
    }
    exec {
        cmd = "git -C " .. dir .. " update-ref HEAD " .. cid,
    }
    return cid
end

-- dry-run merge on the bare repo `dir`: would HEAD+other merge
-- cleanly? merge-tree computes the tree with no worktree, so
-- there is nothing to abort. Unrelated histories fail too
function DRYMERGE (dir, other)
    local ok = exec { err=false, stderr=false,
        cmd = "git -C " .. dir .. " merge-base HEAD " .. other,
    }
    if not ok then
        return false
    end
    local _, code = exec { err=false, stderr=false,
        cmd = "git -C " .. dir .. " merge-tree --write-tree HEAD " .. other,
    }
    return code == 0
end

-- the state snapshot at `dir`'s HEAD (blob at refs/states/<hash>)
function STATE (dir)
    local hash = exec {
        cmd = "git -C " .. dir .. " rev-parse HEAD",
    }
    local src = exec { trim=false,
        cmd = "git -C " .. dir .. " cat-file blob refs/states/" .. hash,
    }
    return load(src)()
end

-- run a command expected to FAIL; assert the error msg if given; return it
function FAIL (t)
    local _, code, err = exec { err=false,
        cmd = t.cmd,
    }
    assert(code ~= 0, "should fail: " .. tostring(err))
    if t.err then
        -- failure output is raw (untrimmed): trailing newline
        assert(err == t.err .. "\n", "should fail with: " .. tostring(err))
    end
    return err
end

-- consensus order of `chain` in the peer `exe`: the array (positions)
-- and the set (membership). Take whichever the assertion needs.
function ORDER (exe, chain)
    local out = exec {
        cmd = exe .. " chain '" .. chain .. "' list order",
    }
    local T = {}
    local S = {}
    for line in out:gmatch("[^\n]+") do
        T[#T+1] = line
        S[line] = true
    end
    return T, S
end

-- reps of the author `pub`. The `exec` call is parenthesized: it also
-- returns the exit code, which `tonumber` would take as the base.
function REPS (exe, chain, pub)
    return tonumber((exec {
        cmd = exe .. " chain '" .. chain .. "' reps author '" .. pub .. "'",
    }))
end

