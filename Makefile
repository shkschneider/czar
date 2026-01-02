# Build system for CZar C semantic authority layer
CC     ?= cc
STD    ?= c11
OPT    ?= O2
CFLAGS := -std=$(STD) -Wall -Wextra -$(OPT)
LDFLAGS = -lc
OUT    ?= build/cz

SOURCES = $(wildcard bin/*.c)
OBJECTS = $(patsubst bin/%.c,build/%.o,$(SOURCES))

# Binary
all: $(OUT)
$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)
./build/%.o: bin/%.c
	@mkdir -p ./build
	$(CC) $(CFLAGS) -c $< -o $@

# Tests: test FILE=...
TESTS = $(wildcard tests/*.cz)
.PHONY: $(TESTS)
ifdef FILE
test: $(OUT)
	@$(MAKE) $(basename $(FILE)).out
else
test: $(TESTS:.cz=.out)
	@echo "All tests passed."
endif
tests/%.out: tests/%.cz $(OUT)
	@echo "- $@"
# preprocessor
	@$(CC) $(CFLAGS) -E -x c $< -o $(<:.cz=.pp.cz)
# transpiler
	@./$(OUT) $(<:.cz=.pp.cz) $(<:.cz=.cz.c)
	@rm -f $(<:.cz=.pp.cz)
# compiler
	@$(CC) $(CFLAGS) -c $(<:.cz=.cz.c) -o $(<:.cz=.o)
# linker
	@$(CC) $(CFLAGS) $(<:.cz=.o) $(LDFLAGS) -o $@
# test
	@./$@ >/dev/null || { rc=$$?; echo "FAILURE: tests/$*.out exited $$rc"; exit $$rc; }

# Cleanup
clean:
	@rm -rvf ./build
	@rm -vf ./tests/*.pp.* ./tests/*.cz.c ./tests/*.o ./tests/*.out
