# Build system for CZar C semantic authority layer
CC     ?= cc
STD    ?= c11
CFLAGS := -std=$(STD) -Wall -Wextra -pedantic -O2
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
	@./$(OUT) $< $<.c
	@$(CC) $(CFLAGS) $<.c $(LDFLAGS) -o $@
	@./$@ >/dev/null || { rc=$$?; echo "FAILURE: tests/$*.out exited $$rc"; exit $$rc; }

# Cleanup
clean:
	@rm -rvf ./build
	@rm -vf ./tests/*.pp.* ./tests/*.cz.c ./tests/*.o ./tests/*.out
