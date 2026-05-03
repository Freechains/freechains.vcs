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
        ["freechains.argparse"]     = "src/freechains/argparse.lua",
        ["freechains.common"]       = "src/freechains/common.lua",
        ["freechains.constants"]    = "src/freechains/constants.lua",
        ["freechains.chain"]        = "src/freechains/chain/init.lua",
        ["freechains.chain.common"] = "src/freechains/chain/common.lua",
        ["freechains.chain.get"]    = "src/freechains/chain/get.lua",
        ["freechains.chain.like"]   = "src/freechains/chain/like.lua",
        ["freechains.chain.order"]  = "src/freechains/chain/order.lua",
        ["freechains.chain.post"]   = "src/freechains/chain/post.lua",
        ["freechains.chain.reps"]   = "src/freechains/chain/reps.lua",
        ["freechains.chain.ssh"]    = "src/freechains/chain/ssh.lua",
        ["freechains.chain.sync"]   = "src/freechains/chain/sync.lua",
        ["freechains.chains"]       = "src/freechains/chains.lua",
    },
    install = {
        bin = {
            freechains = "src/freechains.lua",
        },
    },
}
