L = cd tst && LUA_PATH="../src/?.lua;../src/?/init.lua;;" lua5.4

tests: src/freechains/argparse.lua
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	$(L) ssh.lua
	$(L) git-merge.lua
	$(L) cli-chains.lua
	$(L) cli-post.lua
	$(L) cli-sign.lua
	$(L) cli-like.lua
	$(L) cli-reps.lua
	$(L) cli-now.lua
	$(L) cli-time.lua
	$(L) cli-begs.lua
	$(L) cli-sync.lua
	$(L) err-post.lua
	$(L) err-like.lua
	$(L) repl-local-head.lua
	$(L) repl-remote-head.lua
	$(L) repl-local-begs.lua
	$(L) repl-remote-begs.lua
	@rm -Rf /tmp/freechains/

test: src/freechains/argparse.lua
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	$(L) $(T).lua
	@rm -Rf /tmp/freechains/

src/freechains/argparse.lua:
	curl -sL -o $@ \
	  https://raw.githubusercontent.com/luarocks/argparse/0.7.1/src/argparse.lua

install: src/freechains/argparse.lua
	sudo luarocks --lua-version=5.4 make freechains-0.20-1.rockspec

clean:
	rm -f src/freechains/argparse.lua
