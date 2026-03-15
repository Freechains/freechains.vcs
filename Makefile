tests: src/argparse.lua
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chains.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-post.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-sign.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-like.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-reps.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-now.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-time.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 repl-local.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 repl-remote.lua
	@rm -Rf /tmp/freechains/

test: src/argparse.lua
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 $(T).lua
	@rm -Rf /tmp/freechains/

src/argparse.lua:
	curl -sL -o $@ \
	  https://raw.githubusercontent.com/luarocks/argparse/0.7.1/src/argparse.lua

install: src/argparse.lua
	install -m 755 src/freechains /usr/local/bin/freechains
	install -m 644 src/argparse.lua \
	  /usr/local/share/lua/5.4/

clean:
	rm -f src/argparse.lua
