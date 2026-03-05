all: src/argparse.lua

tests: src/argparse.lua
	@rm -Rf /tmp/freechains/
	@mkdir /tmp/freechains/
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chains.lua
	cd tst && LUA_PATH="../src/?.lua;;" lua5.4 cli-chain.lua
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
