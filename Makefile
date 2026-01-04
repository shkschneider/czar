# Build system for CZar C semantic authority layer
CC     ?= cc -v
STD    ?= c11#-D_POSIX_C_SOURCE=200809L
OPT    ?= O2
CFLAGS := -std=$(STD) -Wall -Wextra -Wno-unknown-pragmas -$(OPT)
LDFLAGS = -static -lc
OUT    ?= build/cz

SOURCES = $(wildcard src/*.c) $(wildcard src/**/*.c)
OBJECTS = $(patsubst src/%.c,build/%.o,$(SOURCES))

# Binary
all: $(OUT)
	@echo
	@file ./$(OUT)
$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)
build/%.o: src/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@
.PHONY: all

# Tests: test FILE=...
TESTS = $(wildcard tests/*.cz)
ifdef FILE
test: $(OUT)
	@$(MAKE) $(basename $(FILE)).out
else
test: $(TESTS:.cz=.out) $(OUT)
	@echo
	@echo "All tests passed."
endif
tests/%.out: tests/%.cz $(OUT)
	@echo "- $@"
	@./$(OUT) $< $<.c >/dev/null
	@$(CC) $(CFLAGS) -c $<.c -o $<.o
	@$(CC) $(CFLAGS) $<.o $(LDFLAGS) -o $@
	@./$@ >/dev/null 2>/dev/null || { rc=$$?; echo "FAILURE: tests/$*.out exited $$rc"; exit $$rc; }
.PHONY: test $(TESTS)

# Cleanup
stat:
	@find src -type f -name "*.c" | xargs wc -l | cut -c2-
	@find tests -type f -name "*.cz" | wc -l | xargs -I{} printf '%5d tests/*.cz' "{}"
clean:
	@rm -rvf ./build
	@rm -vf ./tests/*.pp.cz ./tests/*.cz.c ./tests/*.o ./tests/*.out
.PHONY: clean
