VERSION = {0, 20, 0}
PORT    = 8330

function version ()
    return "v" .. VERSION[1] .. "." .. VERSION[2] .. "." .. VERSION[3]
end

function ERROR (msg, out)
    io.stderr:write("ERROR : " .. msg .. "\n")
    if out then
        io.stderr:write(">>>\n" .. out .. "<<<\n")
    end
    os.exit(1)
end

function exec (t)
    -- t.stderr == false: silences stderr ("2>/dev/null")
    local redir = (t.stderr == false) and "/dev/null" or "&1"
    local h = io.popen(t.cmd .. " 2>" .. redir)
    local out = h:read("a")
    if t.trim ~= false then
        out = out:match("^([^\n]*)\n$") or out
    end
    local _, _, code = h:close()
    if code == 0 then
        return out, code
    elseif t.err == false then
        if out == "" then
            out = nil
        end
        return false, code, out
    elseif t.err then
        if out == "" then
            out = nil
        end
        ERROR(t.err, out)
    else
        error("bug found : [" .. code .. "] : " .. t.cmd .. " : " .. out)
    end
end

function serial (t)
    local function val (v)
        if type(v) == 'boolean' then
            return tostring(v)
        elseif type(v) == 'number' then
            return tonumber(v)
        elseif type(v) == 'string' then
            assert(not string.find(v,'"'))
            return '"' .. v .. '"'
        elseif type(v) ~= 'table' then
            error("TODO : unsupported type")
        else
            local keys = {}
            for k in pairs(v) do keys[#keys+1] = k end
            table.sort(keys)
            local out = {"{\n"}
            for _, k in ipairs(keys) do
                local pfx
                if type(k) == 'number' then
                    pfx = "[" .. k .. "] = "
                else
                    pfx = '["' .. k .. '"] = '
                end
                out[#out+1] = "    " .. pfx .. val(v[k]) .. ",\n"
            end
            out[#out+1] = "}"
            return table.concat(out)
        end
    end
    return "return " .. val(t) .. "\n"
end

-- REVOKED when either the author's or the community's net revoke sum is negative.
function is_revoked (p)
    local r = p.revoke or {}
    return ((r.author or 0) < 0) or ((r.others or 0) < 0)
end

-- Blob hashes of every REVOKED post according to the `state/posts.lua`
-- committed at `ref`. These are the ONLY objects a peer is allowed to
-- be unable to serve: it dropped them on purpose. Anything else it
-- cannot serve makes it a peer we should not be onboarding from.
function revoked_blobs (dir, ref)
    local T = {}
    local src = exec { stderr=false, err=false,
        cmd = "git -C " .. dir .. " show " .. ref .. ":.freechains/state/posts.lua",
    }
    if not src then
        return T
    end
    local f = load(src)
    local ok, posts = pcall(f)
    if not (ok and type(posts) == 'table') then
        return T
    end
    for hash, p in pairs(posts) do
        if is_revoked(p) then
            local file = (exec { stderr=false, err=false,
                cmd = "git -C " .. dir .. " diff-tree --no-commit-id -r --name-only " .. hash,
            } or ""):match("(%S+)")
            local blob = file and exec { stderr=false, err=false,
                cmd = "git -C " .. dir .. " rev-parse " .. hash .. ":" .. file,
            }
            if blob then
                T[blob] = true
            end
        end
    end
    return T
end

-- Objects reachable from `tips` that this repo does not have.
-- `rev-list --missing=print` prefixes those with '?'.
function missing_objects (dir, tips)
    local out = exec { err=false,
        cmd = "git -C " .. dir .. " rev-list --objects --missing=print " .. tips,
    }
    local T = {}
    if out then
        for h in out:gmatch("%?(%x+)") do
            T[#T+1] = h
        end
    end
    return T
end

-- Which of `hashes` (an array) this repo does not actually have.
-- Unlike `missing_objects` this asks about loose hashes rather than
-- what is reachable from a tip, so it also answers for a tree that is
-- not yet pointed at by any ref. GIT_NO_LAZY_FETCH: a `--filter` clone
-- leaves a promisor behind and `cat-file` would silently go fetch the
-- object over the network instead of reporting it absent.
local function absent (dir, hashes)
    local T = {}
    if #hashes == 0 then
        return T
    end
    local out = exec { stderr=false, err=false,
        cmd = "printf '%s\\n' " .. table.concat(hashes, " ") ..
              " | GIT_NO_LAZY_FETCH=1 git -C " .. dir .. " cat-file --batch-check",
    }
    for h in (out or ""):gmatch("(%x+) missing") do
        T[h] = true
    end
    return T
end

-- Point `dir`'s working tree at `tree` (default: HEAD), WITHOUT
-- touching a payload this node does not hold.
--
-- Replaces the porcelain that would do it -- `merge`, `checkout`,
-- `reset --hard`, `clone`'s implicit checkout -- because none of them
-- can be talked out of reading a blob that is gone. `--skip-worktree`
-- does not save them either: they validate the index entry before
-- consulting the bit and die with "unable to read <blob>" on a path
-- they are merely ADDING. So drive it by hand:
--
--   read-tree      index := that tree, by hash; never opens a blob
--   skip-worktree  on exactly the paths whose blob is absent
--   checkout -- .  write the rest; the marked paths are left alone
--
-- read-tree wipes the index clean each time, so the marks are rebuilt
-- from what is ACTUALLY missing right now -- a payload that came back
-- simply stops being marked and lands in the working tree again.
--
-- `checkout -- .` only ever writes, so paths the new tree drops are
-- removed here by hand; git's own checkout is what used to do that.
--
-- Moving HEAD is the caller's job (`update-ref`, `symbolic-ref`): those
-- are pure ref writes, and keeping them out here is what lets the same
-- function serve a fast-forward, a branch switch and a merge result.
function checkout (dir, tree)
    local gone = {}
    for path in (exec { cmd = "git -C " .. dir .. " ls-files" }):gmatch("[^\n]+") do
        gone[path] = true
    end

    exec {
        cmd = "git -C " .. dir .. " read-tree " .. (tree or "HEAD"),
    }

    local hashes, paths = {}, {}
    local idx = exec {
        cmd = "git -C " .. dir .. " ls-files -s",
    }
    for h, path in idx:gmatch("%d+ (%x+) %d+\t([^\n]+)") do
        gone[path] = nil
        if not paths[h] then
            paths[h] = {}
            hashes[#hashes+1] = h
        end
        table.insert(paths[h], path)
    end

    for path in pairs(gone) do
        os.remove(dir .. "/" .. path)
    end
    for h in pairs(absent(dir, hashes)) do
        for _, path in ipairs(paths[h]) do
            exec { err=false,
                cmd = "git -C " .. dir .. " update-index --skip-worktree '" .. path .. "'",
            }
        end
    end

    exec { stderr=false, err=false,
        cmd = "git -C " .. dir .. " checkout -- .",
    }
end

-- Fetch `want` (an array of object hashes) from `url` BY HASH.
--
-- A fetch REQUEST is all-or-nothing: one absent hash sinks the whole
-- batch and its available siblings are NOT delivered. So try one
-- optimistic batch -- a single round trip whenever everything asked
-- for is there -- and only on failure retry per object, where the
-- available ones land and the absent ones fail individually.
--
-- --no-write-fetch-head: a by-hash fetch would otherwise point
-- FETCH_HEAD at the object, clobbering the tip a caller may still
-- need.
function fetch_objects (dir, url, want)
    if #want == 0 then
        return
    end
    table.sort(want)    -- deterministic request order
    local F = "git -C " .. dir .. " fetch --no-write-fetch-head " .. url .. " "
    local ok = exec { stderr=false, err=false,
        cmd = F .. table.concat(want, " "),
    }
    if not ok then
        for _, h in ipairs(want) do
            exec { stderr=false, err=false, cmd = F .. h }
        end
    end
end

-- git refuses to register a promisor remote whose name begins with
-- '/', and --filter cannot run without one, so a bare absolute path
-- fails outright with "did not send all necessary objects". file:// is
-- the same transport under a name git will accept.
function FILTERABLE (url)
    if url:sub(1,1) == "/" then
        return "file://" .. url
    end
    return url
end

function URL (raw, alias)
    if not raw:find("#") then
        local sep = (raw:sub(-1) == "/") and "" or "/"
        raw = raw .. sep .. alias
    end
    if raw:match("^[/~.]") or raw:find("://") then
        return raw
    end
    local hostport, path = raw:match("^([^/]+)(/?.*)$")
    if not hostport:find(":") then
        hostport = hostport .. ":" .. PORT
    end
    return "git://" .. hostport .. path
end

