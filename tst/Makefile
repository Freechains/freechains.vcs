all: a

a: a1 a2 a3 a4
	@echo "--- Section A: all passed ---"

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

clean:
	rm -rf /tmp/freechains/tests/

.PHONY: all a a1 a2 a3 a4 clean
