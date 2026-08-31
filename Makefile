L = cd tst && LUA_PATH="../src/?.lua;../src/?/init.lua;;" lua5.4

tests:
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	@chmod 600 tst/ssh/key*
	$(L) ssh.lua
	$(L) git-merge.lua
	$(L) cli-chains.lua
	$(L) cli-post.lua
	$(L) cli-sign.lua
	$(L) cli-like.lua
	$(L) cli-get.lua
	$(L) cli-reps.lua
	$(L) cli-open.lua
	$(L) cli-dictator.lua
	$(L) cli-revoke.lua
	$(L) cli-now.lua
	$(L) cli-time.lua
	$(L) cli-begs.lua
	$(L) cli-get-merge.lua
	$(L) cli-daemon.lua
	$(L) cli-recv.lua
	$(L) cli-send.lua
	$(L) cli-list.lua
	$(L) cli-abandon.lua
	$(L) cid-edges.lua
	$(L) abandon-strange.lua
	$(L) cli-sweep.lua
	$(L) list-dag-roots.lua
	$(L) sync.lua
	$(L) consensus-gap.lua
	$(L) reorder-ancient.lua
	$(L) climb-underflow.lua
	$(L) climb-underflow-gap.lua
	$(L) bug-climb-ancestor.lua
	$(L) hardfork-shared.lua
	$(L) hardfork-ff.lua
	$(L) fork-7-days.lua
	$(L) err-post.lua
	$(L) err-like.lua
	$(L) bug-err-kind.lua
	$(L) repl-local-head.lua
	$(L) repl-remote-head.lua
	$(L) repl-local-begs.lua
	$(L) repl-remote-begs.lua
	$(L) bug-now-skew.lua
	# slow tests last (many posts / big chains)
	$(L) consensus.lua
	$(L) fork-100-posts.lua
	@rm -Rf /tmp/freechains/

test:
	@rm -Rf /tmp/freechains/
	@mkdir -p /tmp/freechains/
	@chmod 600 tst/ssh/key*
	$(L) $(T).lua
	@rm -Rf /tmp/freechains/

install:
	sudo luarocks --lua-version=5.4 make freechains-dev-2.rockspec
