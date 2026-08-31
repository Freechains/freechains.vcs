#!/usr/bin/env lua5.4

require "tests"

-- A DICTATOR is never gated, in a chain that gates everyone else.
-- It is an ordinary author otherwise: it pays, mints and may owe.
-- Its side also wins a fork outright, whatever the reps say.

local DIC = "--pioneer='" .. PUB1 .. "' --dictator='" .. PUB2 .. "'"

exec {
    cmd = ENV_EXE .. " --now=0 chains add /cli-dic init " .. DIC,
}

do
    print("==> Genesis: pioneers and dictators are distinct")

    do
        TEST "the dictator is marked, and holds no reps"
        local A = STATE(ROOT .. "/chains/cli-dic/").authors
        assert(A[PUB1].reps == 50000, "pioneer split: " .. A[PUB1].reps)
        assert(A[PUB1].dictator == nil, "a pioneer is not a dictator")
        assert(A[PUB2].reps == 0, "dictator reps: " .. A[PUB2].reps)
        assert(A[PUB2].dictator == true, "dictator not marked")

        TEST "a dictator chain is NOT open"
        assert(STATE(ROOT .. "/chains/cli-dic/").open == false, "must be gated")
    end
end

do
    print("==> Gates: the dictator passes, everyone else does not")

    do
        TEST "an unknown key is refused"
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /cli-dic post inline 'x' --sign " .. KEY3,
            err = "ERROR : chain post : insufficient reputation",
        }
    end

    local P
    do
        TEST "the dictator posts from zero reps"
        local out, code = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dic post inline 'by the dictator'"
                .. " --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        P = out

        TEST "and pays for it, going into debt"
        -- never gated, but the economy still applies
        local r = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dic reps author '" .. PUB2 .. "'",
        }
        assert(r == "-500", "dictator reps: " .. r)
    end

    do
        TEST "the dictator votes beyond its balance"
        local _, code = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dic like 1000 author '" .. PUB3
                .. "' --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local r = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dic reps author '" .. PUB2 .. "'",
        }
        assert(r == "-1500", "dictator reps: " .. r)

        TEST "so it can admit anyone"
        -- KEY3 was refused above, and now holds reps
        local r3 = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dic reps author '" .. PUB3 .. "'",
        }
        assert(r3 == "900", "welcomed reps: " .. r3)
    end

    do
        TEST "begging still works: a dictator chain admits"
        local out, code = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dic post inline 'beg' --beg",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local begs = exec {
            cmd = ENV_EXE .. " chain /cli-dic list begs",
        }
        assert(begs == out, "the beg should be parked: " .. begs)
    end
end

-- The dictator side wins a fork outright, even against the
-- pioneer holding every rep in the chain.
do
    print("==> Consensus: the dictator side wins outright")

    local A = ROOT .. "/cli-dic-A/"
    local B = ROOT .. "/cli-dic-B/"
    local EXE_A = ENV .. " ../src/freechains.lua --root " .. A
    local EXE_B = ENV .. " ../src/freechains.lua --root " .. B

    exec { cmd = EXE_A .. " --now=0 chains add /fork init " .. DIC }
    exec { cmd = EXE_B .. " chains add /fork clone " .. A .. "/chains/fork" }

    do
        TEST "the floor: the pioneer holds everything"
        local a = exec {
            cmd = EXE_B .. " --now=0 chain /fork reps author '" .. PUB1 .. "'",
        }
        local d = exec {
            cmd = EXE_B .. " --now=0 chain /fork reps author '" .. PUB2 .. "'",
        }
        assert(a == "50000", "pioneer: " .. a)
        assert(d == "0", "dictator: " .. d)
    end

    local PA = exec {
        cmd = EXE_A .. " --now=100 chain /fork post inline 'pioneer' --sign " .. KEY1,
    }
    local PB = exec {
        cmd = EXE_B .. " --now=100 chain /fork post inline 'dictator' --sign " .. KEY2,
    }
    exec { cmd = EXE_B .. " --now=200 chain /fork sync recv " .. A .. "/chains/fork" }

    do
        TEST "50000 reps lose to the dictator mark"
        local O = ORDER(EXE_B, "/fork")
        assert(O[#O-1] == PB, "dictator side should win: " .. tostring(O[#O-1]))
        assert(O[#O]   == PA, "pioneer side should lose: " .. tostring(O[#O]))
    end
end

-- A key may hold BOTH roles: it takes the pioneer split AND the
-- mark. Neither cancels the other.
do
    print("==> Both roles: a key may be pioneer and dictator")

    local DUAL = ROOT .. "/chains/cli-dual/"
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-dual init"
            .. " --pioneer='" .. PUB1 .. "' --pioneer='" .. PUB2 .. "'"
            .. " --dictator='" .. PUB1 .. "'",
    }

    do
        TEST "the genesis lists the key twice: bare, then marked"
        local t = GENESIS(DUAL)
        assert(#t.pioneers  == 2, "pioneers: "  .. #t.pioneers)
        assert(#t.dictators == 1, "dictators: " .. #t.dictators)
        assert(t.dictators[1] == PUB1, "the dual key is not marked")

        TEST "it holds the pioneer split AND the mark"
        local A = STATE(DUAL).authors
        assert(A[PUB1].reps == 25000, "dual reps: " .. A[PUB1].reps)
        assert(A[PUB1].dictator == true, "dual not marked")
        assert(A[PUB2].reps == 25000, "plain reps: " .. A[PUB2].reps)
        assert(A[PUB2].dictator == nil, "plain must not be marked")
    end

    -- the two pioneers start equal: only the mark tells them apart
    do
        TEST "both spend their whole balance on a vote"
        for _, k in ipairs { KEY1, KEY2 } do
            exec {
                cmd = ENV_EXE .. " --now=0 chain /cli-dual like 25000 author '"
                    .. PUB4 .. "' --sign " .. k,
            }
        end
        local a = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dual reps author '" .. PUB1 .. "'",
        }
        local b = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dual reps author '" .. PUB2 .. "'",
        }
        assert(a == "0", "dual reps: "  .. a)
        assert(b == "0", "plain reps: " .. b)

        TEST "at zero, the dual key still posts"
        local _, code = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-dual post inline 'dual'"
                .. " --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))

        TEST "at zero, the plain pioneer is refused"
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /cli-dual post inline 'plain'"
                .. " --sign " .. KEY2,
            err = "ERROR : chain post : insufficient reputation",
        }
    end
end

-- Dictators need no pioneer: a chain may be owned outright.
do
    print("==> Two dictators: both marked, the chain still gates")

    local TWO = ROOT .. "/chains/cli-two/"
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-two init"
            .. " --dictator='" .. PUB2 .. "' --dictator='" .. PUB3 .. "'",
    }

    do
        TEST "both are marked, and neither holds reps"
        local G = STATE(TWO)
        assert(#GENESIS(TWO).dictators == 2, "two dictator lines")
        assert(G.authors[PUB2].dictator == true, "PUB2 not marked")
        assert(G.authors[PUB3].dictator == true, "PUB3 not marked")
        assert(G.authors[PUB2].reps == 0, "PUB2 reps: " .. G.authors[PUB2].reps)
        assert(G.authors[PUB3].reps == 0, "PUB3 reps: " .. G.authors[PUB3].reps)

        TEST "no pioneer, but dictators: the chain is NOT open"
        assert(G.open == false, "must be gated")
    end

    do
        TEST "each dictator posts from zero, and pays"
        for _, t in ipairs { {KEY2,PUB2}, {KEY3,PUB3} } do
            local _, code = exec {
                cmd = ENV_EXE .. " --now=0 chain /cli-two post inline 'x'"
                    .. " --sign " .. t[1],
            }
            assert(code == 0, "exit code: " .. tostring(code))
            local r = exec {
                cmd = ENV_EXE .. " --now=0 chain /cli-two reps author '" .. t[2] .. "'",
            }
            assert(r == "-500", "dictator reps: " .. r)
        end

        TEST "a stranger is still refused"
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /cli-two post inline 'x'"
                .. " --sign " .. KEY4,
            err = "ERROR : chain post : insufficient reputation",
        }

        TEST "and so is an unsigned post: the chain is not open"
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /cli-two post inline 'x'",
            err = "ERROR : chain post : requires --sign or --beg",
        }
    end
end

print("<== ALL PASSED")
