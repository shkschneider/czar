# Build system for CZar C semantic authority layer
CC     ?= cc -v
STD    ?= c11
OPT    ?= O2
CFLAGS := -std=$(STD) -Wall -Wextra -Werror -Wno-unknown-pragmas -$(OPT)
LDFLAGS = -static -lc
OUT     = cz
BIN    ?= dist/$(OUT)
LIB_A  ?= dist/lib$(OUT)ar.a
LIB_SO ?= dist/lib$(OUT)ar.so

BIN_SRC = $(wildcard *.c) $(wildcard src/*.c)
BIN_OBJ = $(patsubst %.c,build/%.o,$(BIN_SRC))
LIB_SRC = $(wildcard lib/*.c)
LIB_OBJ = $(patsubst %.c,build/%.o,$(LIB_SRC))
TESTS   = $(wildcard test/*.cz)

all: bin lib
dist: bin lib
.PHONY: all dist

# Binary
bin: $(BIN)
	@echo -n "[CZ] " ; file $<
build/%.o: %.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@
$(BIN): $(BIN_OBJ)
	@mkdir -p $(@D)
	$(CC) $^ $(LDFLAGS) -o $@
.PHONY: bin

# Library
lib: $(LIB_A) $(LIB_SO)
build/lib/%.o: lib/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -fPIC -c $< -o $@
$(LIB_A): $(LIB_OBJ) dist/cz.h
	@mkdir -p $(@D)
	ar rcs $@ $(LIB_OBJ)
	ranlib $@
	@echo -n "[CZ] " ; file $@
$(LIB_SO): $(LIB_OBJ) dist/cz.h
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -shared $(LIB_OBJ) -o $@
	@echo -n "[CZ] " ; file $@
dist/cz.h: lib/cz.h
	cp -v lib/cz.h dist/ >/dev/null
.PHONY: lib

# Tests
test: test/app test/lib $(TESTS:.cz=)
	@echo "All tests passed."
test/app: $(BIN)
	@echo "- $@"
	@$(MAKE) -C $@ >/dev/null
test/lib:
	@echo "- $@"
	@$(MAKE) -C $@ >/dev/null
test/%: test/%.cz $(BIN)
	@echo "- $@"
	@./$(BIN) $< >/dev/null
	@$(CC) $(CFLAGS) -c $<.c -o $<.o
	@$(CC) $(CFLAGS) $<.o $(LDFLAGS) -o $@
	@./$@ >/dev/null 2>/dev/null
.PHONY: test test/app $(TESTS)

# Cleanup
stat:
	@find $(BIN_SRC) | xargs wc -l | cut -c2- | sort -n
	@grep -o ';' $(BIN_SRC) | wc -l | xargs -I{} printf '%5d statements\n' "{}"
	@ctags -x --c-types=f $(BIN_SRC) | cut -d' ' -f1 | sort -u | wc -l | xargs -I{} printf '%5d functions\n' "{}"
	@find ./test -type f -name "*.cz" | wc -l | xargs -I{} printf '%5d tests/*.cz\n' "{}"
clean:
	@rm -rf ./build/
	@find ./test \( -name "*.cz.h" -o -name "*.cz.c" \) -exec rm -vf {} \;
	@find ./test -type f \( -name "*.o" -o -executable \) -exec rm -vf {} \;
	@find ./test -type f \( -name "*.a" -o -name "*.so" \) -exec rm -vf {} \;
distclean: clean
	@rm -rvf $(BIN) $(LIB_A) $(LIB_SO)
.PHONY: stat clean distclean
