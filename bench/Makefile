CC        ?= cc
CZ        ?= ../build/cz
SRC        = fibonacci
CFLAGS     = -std=c11 -Wall -Wextra -O2
LDFLAGS    = -lc
OUT_C      = c.out
OUT_CZ     = cz.out
TESTS      = 11 22 33 42

all: $(CZ) $(OUT_C) $(OUT_CZ)
ifeq ($(shell command -v hyperfine 2>/dev/null),)
	$(error "E: github.com/sharkdp/hyperfine not found!")
endif
	hyperfine --warmup 1 "./$(OUT_C) $(TESTS)" "./$(OUT_CZ) $(TESTS)"

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
