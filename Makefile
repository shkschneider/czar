# Build system for CZar C semantic authority layer
CC     ?= cc -v
STD    ?= c11
OPT    ?= O2
CFLAGS := -std=$(STD) -Wall -Wextra -Wno-unknown-pragmas -I./src -$(OPT)
LDFLAGS = -static -lc
OUT    ?= build/cz

BIN_SOURCES = $(wildcard bin/*.c)
SRC_SOURCES = $(wildcard src/*.c)
BIN_OBJECTS = $(patsubst bin/%.c,build/bin/%.o,$(BIN_SOURCES))
SRC_OBJECTS = $(patsubst src/%.c,build/src/%.o,$(SRC_SOURCES))
OBJECTS = $(BIN_OBJECTS) $(SRC_OBJECTS)

# Binary
all: $(OUT)
$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)
build/bin/%.o: bin/%.c
	@mkdir -p ./build/bin
	$(CC) $(CFLAGS) -c $< -o $@
build/src/%.o: src/%.c
	@mkdir -p ./build/src
	$(CC) $(CFLAGS) -c $< -o $@
.PHONY: all

# Demo
demo/a.out:
	$(MAKE) -B -C demo -o $@
demo: demo/a.out
	@./$<
.PHONY: demo

# Tests: test FILE=...
TESTS = $(wildcard tests/*.cz)
ifdef FILE
test: $(OUT)
	@$(MAKE) $(basename $(FILE)).out
else
test: demo $(TESTS:.cz=.out)
	@grep -R "cz_" tests/*.cz && { echo "FAILURE: grep -R 'cz_' found old-style types"; exit 1; } || true
	@echo "All tests passed."
endif
tests/%.out: tests/%.cz $(OUT)
	@echo "- $@"
# transpiler (works on raw .cz file, adds required headers)
	@./$(OUT) $< $(<:.cz=.cz.c)
# compiler (preprocesses and compiles in one step)
	@$(CC) $(CFLAGS) -c $(<:.cz=.cz.c) -o $(<:.cz=.o)
# linker
	@$(CC) $(CFLAGS) $(<:.cz=.o) $(LDFLAGS) -o $@
# test
	@./$@ >/dev/null 2>/dev/null || { rc=$$?; echo "FAILURE: tests/$*.out exited $$rc"; exit $$rc; }
.PHONY: test $(TESTS)

# Cleanup
clean:
	@rm -rvf ./build
	@rm -vf ./demo/*.pp.cz ./demo/*.cz.c ./demo/*.o ./demo/*.out
	@rm -vf ./tests/*.pp.cz ./tests/*.cz.c ./tests/*.o ./tests/*.out
.PHONY: clean
