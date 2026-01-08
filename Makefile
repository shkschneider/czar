# Build system for CZar C semantic authority layer
CC     ?= cc -v
STD    ?= c11
OPT    ?= O2
CFLAGS := -std=$(STD) -Wall -Wextra -Werror -Wno-unknown-pragmas -$(OPT)
LDFLAGS = -static -lc
OUT    ?= build/cz

# Binary
SOURCES = $(wildcard *.c) $(wildcard src/*.c)
OBJECTS = $(patsubst src/%.c,build/%.o,$(SOURCES))
all: $(OUT)
	@file ./$(OUT)
$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)
build/%.o: src/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@
.PHONY: all

# Tests
TESTS = $(wildcard test/*.cz)
test: $(OUT) $(TESTS:.cz=) $(OUT)
	@echo "All tests passed."
test/%: test/%.cz $(OUT)
	@echo "- $@"
	@./$(OUT) $< $<.c >/dev/null
	@$(CC) $(CFLAGS) -c $<.c -o $<.o
	@$(CC) $(CFLAGS) $<.o $(LDFLAGS) -o $@
	@./$@ >/dev/null 2>/dev/null
.PHONY: test $(TESTS)

# Cleanup
stat:
	@find ./src -type f -name "*.c" | xargs wc -l | cut -c2- | sort -n
	@grep -Ro ';' *.c ./src/ | wc -l | xargs -I{} printf '%5d statements\n' "{}"
	@find ./test -type f -name "*.cz" | wc -l | xargs -I{} printf '%5d tests/*.cz\n' "{}"
clean:
	@rm -rvf ./build/
	@find ./test -type f -name "*.c" -o -name "*.h" -exec rm -vf {} \;
	@find ./test -type f -executable -exec rm -vf {} \;
.PHONY: stat clean
