LUA ?= lua5.4

all: a b

a: a1 a2 a3 a4
	@echo "--- Section A: all passed ---"

b: b1 b2
	@echo "--- Section B: all passed ---"

a-lua: a1-lua a2-lua a3-lua a4-lua
	@echo "--- Section A (Lua): all passed ---"

a1:
	@echo ">>> a1: data round-trip"
	@bash a1.sh

a2:
	@echo ">>> a2: symmetric encryption"
	@bash a2.sh

a3:
	@echo ">>> a3: asymmetric encryption"
	@bash a3.sh

a4:
	@echo ">>> a4: sorted set difference"
	@bash a4.sh

a1-lua:
	@echo ">>> a1: data round-trip (Lua)"
	@$(LUA) a1.lua

a2-lua:
	@echo ">>> a2: symmetric encryption (Lua)"
	@$(LUA) a2.lua

a3-lua:
	@echo ">>> a3: asymmetric encryption (Lua)"
	@$(LUA) a3.lua

a4-lua:
	@echo ">>> a4: sorted set difference (Lua)"
	@$(LUA) a4.lua

b1:
	@echo ">>> b1: host init"
	@bash b1.sh

b2:
	@echo ">>> b2: chain persistence"
	@bash b2.sh

x1:
	@echo ">>> x1: genesis block"
	@bash x1.sh

clean:
	rm -rf /tmp/freechains/tests/

.PHONY: all a b a-lua a1 a2 a3 a4 b1 b2 x1 a1-lua a2-lua a3-lua a4-lua clean
