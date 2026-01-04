CC        ?= cc
CZ        ?= ../build/cz
SRC        = fibonacci
CFLAGS     = -std=c11 -Wall -Wextra -O2
LDFLAGS    = -lc
OUT_C      = c.out
OUT_CZ     = cz.out
TEST       = 11 22 33 42

# https://github.com/sharkdp/hyperfine
all: $(CZ) $(OUT_C) $(OUT_CZ)
	hyperfine --warmup 1 "./$(OUT_C) $(TEST)" "./$(OUT_CZ) $(TEST)"

$(CZ):
	$(MAKE) -C .. -B

.SUFFIXES: # turn off implicit suffix rules (circular dependency)
$(OUT_C): $(CZ)
	$(CC) $(SRC).c -o $(OUT_C)

$(OUT_CZ): $(CZ)
	$(CZ) $(SRC).cz $(SRC).cz.c
	$(CC) $(SRC).cz.c -o $(OUT_CZ)

clean:
	@rm -vf ./*.cz.c ./$(OUT_C) ./$(OUT_CZ)
