all: src/argparse.lua

src/argparse.lua:
	curl -sL -o $@ \
	  https://raw.githubusercontent.com/luarocks/argparse/0.7.1/src/argparse.lua

install: src/argparse.lua
	install -m 755 src/freechains /usr/local/bin/freechains
	install -m 644 src/argparse.lua \
	  /usr/local/share/lua/5.4/

clean:
	rm -f src/argparse.lua
