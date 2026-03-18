tests: src/freechains/argparse.lua
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 git-merge.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chains.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-post.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-sign.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-like.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-reps.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-now.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-time.lua
	#cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-begs.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 repl-local-head.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 repl-remote-head.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 repl-local-begs.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 repl-remote-begs.lua
	@rm -Rf /tmp/freechains/

test: src/freechains/argparse.lua
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 $(T).lua
	@rm -Rf /tmp/freechains/

src/freechains/argparse.lua:
	curl -sL -o $@ \
	  https://raw.githubusercontent.com/luarocks/argparse/0.7.1/src/argparse.lua

install: src/freechains/argparse.lua
	sudo luarocks --lua-version=5.4 make freechains-0.20-1.rockspec

clean:
	rm -f src/freechains/argparse.lua
