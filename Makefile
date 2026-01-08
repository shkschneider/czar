# Build system for CZar C semantic authority layer
CC     ?= cc -v
STD    ?= c11
OPT    ?= O2
CFLAGS := -std=$(STD) -Wall -Wextra -Werror -Wno-unknown-pragmas -$(OPT)
LDFLAGS = -static -lc
OUT    ?= build/cz

# Binary
SOURCES = $(wildcard src/*.c) $(wildcard src/**/*.c)
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
TESTS = $(wildcard test/*.cz) $(wildcard test/*/*.cz)
test: $(OUT) $(TESTS:.cz=) $(OUT)
	@echo "All tests passed."
test/%: test/%.cz $(OUT)
	@echo "- $@"
	@./$(OUT) $< >/dev/null
	@$(CC) $(CFLAGS) -I$(dir $<) -c $<.c -o $<.o
	@$(CC) $(CFLAGS) -I$(dir $<) -c $(dir $<)cz.c -o $(dir $<)cz.o
	@$(CC) $(CFLAGS) $<.o $(dir $<)cz.o $(LDFLAGS) -o $@
	@./$@ >/dev/null 2>/dev/null
.PHONY: test $(TESTS)

# Cleanup
stat:
	@find ./src -type f -name "*.c" | xargs wc -l | cut -c2- | sort -n
	@grep -Ro ';' ./src/ | wc -l | xargs -I{} printf '%5d statements\n' "{}"
	@find ./test -type f -name "*.cz" | wc -l | xargs -I{} printf '%5d tests/*.cz\n' "{}"
clean:
	@rm -rvf ./build/
	@rm -vf ./test/*.pp.cz ./test/*.cz.c ./test/*.cz.h ./test/*.o ./test/cz.c ./test/cz.h
	@rm -vf ./test/app/*.cz.c ./test/app/*.cz.h ./test/app/*.o ./test/app/cz.c ./test/app/cz.h
	@find ./test -type f -executable -exec rm -vf {} \;
.PHONY: stat clean
