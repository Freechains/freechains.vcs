--[[
-- `daemon start|stop`: serve the root's chains via git daemon.
-- Inputs:
--  - ARGS.start|ARGS.stop [boolean]: what to do
--  - ARGS.port [integer?]: listen port (default PORT)
--  - ARGS.hub  [boolean?]: also accept pushes (receive-pack)
--  - ARGS.xtra [table]: extra git daemon arguments
--  - ARGS.root [string]: freechains root dir
-- Outputs:
--  - start: blocks serving; stdout "Serving on port ..."
--  - stop: kills every holder of the port; stdout the pids
-- Errors:
--  - "daemon start : git daemon failed"
--  - "daemon stop : not running"
-- Callers:
--  - dispatch (freechains.lua): ARGS.daemon
--]]

-- Serves the local chains, one daemon per root: `--hub` adds
-- pushes to the fetches `git daemon` already serves, so a root
-- never needs two.
-- `stop` kills by PORT, so it reaches a `start` with `&` and children

local port = ARGS.port or PORT
local base = ARGS.root .. "/chains/"

if ARGS.start then
    local cmd =
        "git daemon --base-path=" .. base ..
        " --export-all" ..
        " --enable=" .. (ARGS.hub and "receive-pack" or "upload-pack") ..
        " --port=" .. port ..
        " --listen=0.0.0.0" ..
        " --reuseaddr" ..
        " " .. table.concat(ARGS.xtra, " ")

    print("Serving on port " .. port .. "...")
    -- `stop` kills us, and a signal is not a failure
    local ok, how = os.execute(cmd)
    if (not ok) and (how ~= "signal") then
        ERROR("daemon start : git daemon failed")
    end

elseif ARGS.stop then
    -- kill by PORT: the `--serve` children INHERIT and outlive parent
    local out = exec { trim=false,
        cmd = "ss -atnp",
    }
    local ns = {}
    for line in out:gmatch("[^\n]+") do
        -- "LISTEN 0 5 0.0.0.0:8330 0.0.0.0:* users:((\"git-daemon\",pid=7,fd=3))"
        local loc, rest = line:match("^%S+%s+%S+%s+%S+%s+(%S+)%s+%S+%s+(.*)$")
        if loc and loc:match(":" .. port .. "$") then
            for n in rest:gmatch("\"git%-daemon\",pid=(%d+)") do
                ns[n] = true
            end
        end
    end
    if next(ns) == nil then
        ERROR("daemon stop : not running")
    end
    for n in pairs(ns) do
        exec { err=false, stderr=false,
            cmd = "kill " .. n,
        }
        print(n)
    end
end
