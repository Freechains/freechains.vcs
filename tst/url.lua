#!/usr/bin/env lua5.4

require "tests"

local ALIAS = "#chat"
local HASH  = "#0123456789abcdef0123456789abcdef01234567"

local CASES = {
    { "1.2.3.4",             "git://1.2.3.4:8330/#chat"        },
    { "1.2.3.4:9999",        "git://1.2.3.4:9999/#chat"        },
    { "1.2.3.4/#other",      "git://1.2.3.4:8330/#other"       },
    { "host/#chat",          "git://host:8330/#chat"           },
    { "host/" .. HASH,       "git://host:8330/" .. HASH        },
    { "git://h:8330",        "git://h:8330/#chat"              },
    { "git://h:8330/",       "git://h:8330/#chat"              },
    { "git://h:8330/#chat",  "git://h:8330/#chat"              },
    { "ssh://bob@h/p",       "ssh://bob@h/p/#chat"             },
    { "ssh://bob@h/#chat",   "ssh://bob@h/#chat"               },
    { "~/peer/chains",       "~/peer/chains/#chat"             },
    { "/srv/chains",         "/srv/chains/#chat"               },
    { "/srv/chains/",        "/srv/chains/#chat"               },
    { "/srv/chains/#chat",   "/srv/chains/#chat"               },
    { "./peer/chains/#chat", "./peer/chains/#chat"             },
    { "host",                "git://host:8330/" .. HASH, HASH  },
}

for _, c in ipairs(CASES) do
    local input, expected, alias = c[1], c[2], c[3] or ALIAS
    TEST (input .. " -> " .. expected)
    local got = URL(input, alias)
    assert(got == expected, "got: " .. tostring(got))
end

print("<== ALL PASSED")
