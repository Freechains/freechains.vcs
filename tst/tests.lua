require "common"

TMP    = "/tmp/freechains/"
GEN    = "genesis/"
GEN_1P = "genesis-1p/"
GEN_2P = "genesis-2p/"
GEN_3P = "genesis-3p/"
ROOT   = TMP .. "/root/"
EXE    = "../src/freechains --root " .. ROOT

GPG     = exec("realpath gnupg/") .. "/"
KEY     = "CA6391CEA51882DF980E0F0C6774E21538E4078B"
KEY2    = "783975D11C5437506E4EF015CC72520488613667"
KEY3    = "F02130B311328E060A909923190C651F0C13FAB1"
ENV     = "GNUPGHOME=" .. GPG
ENV_EXE = ENV .. " " .. EXE

function TEST (name)
    print("  - " .. name .. "... ")
end
