# Build system for CZar C semantic authority layer
# MIT License Copyright (c) 2026 ShkSchneider
# https://github.com/shkschneider/czar

CC      ?= cc -v
$(if $(shell command -v $(CC) 2>/dev/null),,$(error "[CZ] $(CC): command not found"))
STD     ?= c11
OPT     ?= O2
CFLAGS  := $(strip -std=$(STD) -Wall -Wextra -Werror -$(OPT)\
		-Wno-unknown-pragmas -Wno-unused-command-line-argument)
LDFLAGS := -static -lc
OUT      = cz
BIN      = dist/$(OUT)
LIB_A    = dist/lib$(OUT)ar.a
LIB_SO   = dist/lib$(OUT)ar.so

BIN_SRC  = $(wildcard *.c) $(wildcard src/*.c)
BIN_OBJ  = $(patsubst %.c,build/%.o,$(BIN_SRC))
LIB_SRC  = $(wildcard lib/*.c)
LIB_OBJ  = $(patsubst %.c,build/%.o,$(LIB_SRC))
TESTS    = $(wildcard test/*.cz)

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
	@echo "[CZ] $@"
	@mkdir -p $(@D)
	$(CC) $^ $(LDFLAGS) -o $@
.PHONY: bin $(BIN)

# Library
lib: $(LIB_A) $(LIB_SO) dist/$(OUT).h
build/lib/%.o: lib/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -fPIC -c $< -o $@
$(LIB_A): $(LIB_OBJ) dist/$(OUT).h
	@mkdir -p $(@D)
	$(if $(shell command -v ar 2>/dev/null),,$(error "[CZ] ar: command not found"))
	ar rcs $@ $(LIB_OBJ)
	$(if $(shell command -v ranlib 2>/dev/null),ranlib $@,)
	$(if $(shell command -v nm 2>/dev/null), \
		@echo -n "[CZ] $@: "; nm -gU $@ | grep cz_ | rev | cut -d' ' -f1 | rev | xargs, \
		@echo -n "[CZ] "; file $@)
$(LIB_SO): $(LIB_OBJ) dist/$(OUT).h
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -shared $(LIB_OBJ) -o $@
	$(if $(shell command -v objdump 2>/dev/null), \
		@echo -n "[CZ] $@: "; objdump -t $@ | grep cz_ | rev | cut -d' ' -f1 | rev | xargs, \
		@echo -n "[CZ] "; file $@)
dist/$(OUT).h: lib/$(OUT).h
	@echo "[CZ] $@"
	@cp -v $< $(@D)/
.PHONY: lib $(LIB_A) $(LIB_SO) dist/$(OUT).h

# Tests
test: test/app test/lib $(TESTS:.cz=)
	@echo "All tests passed."
test/app: $(BIN)
	@echo "- $@"
	@$(MAKE) -C $@ >/dev/null
test/lib: dist/$(OUT).h
	@echo "- $@"
	@$(MAKE) -C $@ >/dev/null
test/%: test/%.cz $(BIN)
	@echo "- $@"
	@./$(BIN) $< >/dev/null
	@$(CC) $(CFLAGS) -c $<.c -o $<.o
	@$(CC) $(CFLAGS) $<.o $(LDFLAGS) -o $@
	@./$@ >/dev/null 2>/dev/null
.PHONY: test test/app test/lib $(TESTS)

# Miscellaneous
format:
	$(if $(shell command -v clang-format 2>/dev/null), \
		find . -type f -name "*.c" -exec clang-format -i {} \;, \
		$(error "clang-format: command not found") \
	)
stat:
	@echo "[CZ] stat"
	@find $(BIN_SRC) | xargs wc -l | cut -c2- | sort -n
	@grep -o ';' $(BIN_SRC) | wc -l | xargs -I{} printf '%5d statements\n' "{}"
	$(if $(shell command -v ctags 2>/dev/null), \
		@ctags -x --c-types=f $(BIN_SRC) | cut -d' ' -f1 | sort -u | wc -l | xargs -I{} printf '%5d functions\n' "{}", \
	)
	@find ./test -type f -name "*.cz" | wc -l | xargs -I{} printf '%5d tests/*.cz\n' "{}"
clean:
	@echo "[CZ] clean"
	@rm -rf ./build/
	@find ./test \( -name "*.cz.h" -o -name "*.cz.c" \) -exec rm -vf {} \;
	@find ./test -type f \( -name "*.o" -o -executable \) -exec rm -vf {} \;
	@find ./test -type f \( -name "*.a" -o -name "*.so" \) -exec rm -vf {} \;
	@$(MAKE) -C test/app clean
	@$(MAKE) -C test/lib clean
distclean: clean
	@echo "[CZ] distclean"
	@rm -rvf $(BIN) $(LIB_A) $(LIB_SO) dist/$(OUT).h
.PHONY: format stat clean distclean
