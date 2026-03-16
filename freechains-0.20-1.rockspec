package = "freechains"
version = "0.20-1"

source = {
    url = "git+https://github.com/fsantanna/freechains.git",
}

description = {
    summary  = "Permissionless Peer-to-peer Content Dissemination",
    homepage = "https://www.freechains.org/",
    license  = "MIT",
}

dependencies = {
    "lua >= 5.4",
}

build = {
    type = "builtin",
    modules = {
        ["freechains.argparse"]  = "src/freechains/argparse.lua",
        ["freechains.common"]    = "src/freechains/common.lua",
        ["freechains.constants"] = "src/freechains/constants.lua",
        ["freechains.chain"]     = "src/freechains/chain.lua",
        ["freechains.chains"]    = "src/freechains/chains.lua",
    },
    install = {
        bin = {
            freechains = "src/freechains.lua",
        },
    },
}
