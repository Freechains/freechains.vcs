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
--  - stop: kills via the pid file; stdout the pid
-- Errors:
--  - "daemon start : git daemon failed"
--  - "daemon stop : not running"
-- Callers:
--  - dispatch (freechains.lua): ARGS.daemon
--]]

-- Serves the local chains, one daemon per root: `--hub` adds
-- pushes to the fetches `git daemon` already serves, so a root
-- never needs two. `git daemon` owns the pid file, so `stop`
-- reaches a `start` backgrounded with `&`.

local port = ARGS.port or PORT
local base = ARGS.root .. "/chains/"
local pid  = ARGS.root .. "/daemon.pid"

if ARGS.start then
    local cmd =
        "git daemon --base-path=" .. base ..
        " --export-all" ..
        " --enable=" .. (ARGS.hub and "receive-pack" or "upload-pack") ..
        " --port=" .. port ..
        " --pid-file=" .. pid ..
        " " .. table.concat(ARGS.xtra, " ")

    print("Serving on port " .. port .. "...")
    -- `stop` kills us, and a signal is not a failure
    local ok, how = os.execute(cmd)
    if (not ok) and (how ~= "signal") then
        ERROR("daemon start : git daemon failed")
    end

elseif ARGS.stop then
    local f = io.open(pid)
    if not f then
        ERROR("daemon stop : not running")
    end
    local n = f:read("a"):match("%d+")
    f:close()
    os.remove(pid)

    -- kill's own "No such process" adds nothing to our message
    exec { stderr = false,
        cmd = "kill " .. n,
        err = "daemon stop : not running",
    }
    print(n)
end
