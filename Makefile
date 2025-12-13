# Makefile for czar compiler

# Output binary
OUT := cz

# Build directory
BUILD_DIR := ./build

# Source files
LUA_SOURCES := \
	src/main.lua \
	src/lexer/init.lua \
	src/parser/init.lua \
	src/codegen/init.lua \
	src/codegen/types.lua \
	src/codegen/memory.lua \
	src/codegen/functions.lua \
	src/codegen/statements.lua \
	src/codegen/expressions.lua \
	src/generate.lua \
	src/assemble.lua \
	src/build.lua \
	src/run.lua

# Object files (generated from Lua sources)
OBJECTS := $(patsubst src/%.lua,$(BUILD_DIR)/%.o,$(LUA_SOURCES))
OBJECTS := $(subst /,_,$(OBJECTS))

# Library
LIBRARY := $(BUILD_DIR)/libczar.a

# C source
C_SOURCE := $(BUILD_DIR)/main.c
MAIN_HEADER := $(BUILD_DIR)/main.h

# Compiler flags
CFLAGS := $(shell pkg-config --cflags luajit 2>/dev/null) -O2

# Linker flags (conditional based on luastatic availability)
ifeq ($(shell command -v luastatic >/dev/null 2>&1 && echo yes),yes)
    $(info [LUASTATIC] detected, building static binary)
    LDFLAGS := -static -L. -L$(BUILD_DIR) -Wl,--whole-archive -lczar -Wl,--no-whole-archive -Wl,-E $(shell pkg-config --libs luajit 2>/dev/null) -lm -ldl -s
else
    $(info [LUASTATIC] not found, building dynamic binary)
    LDFLAGS := -L. -L$(BUILD_DIR) -Wl,--whole-archive -lczar -Wl,--no-whole-archive -Wl,-E $(shell pkg-config --libs luajit 2>/dev/null) -lm -ldl -s
endif

# Default target
.PHONY: all
all: $(OUT)

# Check dependencies
.PHONY: check-deps
check-deps:
	@echo "[CHECK] Dependencies..."
	@for dep in git pkg-config luajit nm ar cc ; do \
		echo -n "- $$dep: " ; \
		path=$$(command -v $$dep 2>/dev/null) ; \
		if [ -n "$$path" ] ; then \
			echo "$$path" ; \
		else \
			echo "MISSING" ; \
			exit 1 ; \
		fi ; \
	done

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Compile Lua sources to bytecode objects
$(BUILD_DIR)/%.o: src/%.lua | $(BUILD_DIR)
	@name=$$(echo $* | tr '/' '_') ; \
	name=$$(basename $$name .lua) ; \
	echo "[LUAJIT] $< -> $(BUILD_DIR)/$${name}.o" ; \
	luajit -b -n $$name $< $(BUILD_DIR)/$${name}.o

# Special rules for Lua files in subdirectories
$(BUILD_DIR)/lexer_init.o: src/lexer/init.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n lexer_init $< $@

$(BUILD_DIR)/parser_init.o: src/parser/init.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n parser_init $< $@

$(BUILD_DIR)/codegen_init.o: src/codegen/init.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n codegen_init $< $@

$(BUILD_DIR)/codegen_types.o: src/codegen/types.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n codegen.types $< $@

$(BUILD_DIR)/codegen_memory.o: src/codegen/memory.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n codegen.memory $< $@

$(BUILD_DIR)/codegen_functions.o: src/codegen/functions.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n codegen.functions $< $@

$(BUILD_DIR)/codegen_statements.o: src/codegen/statements.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n codegen.statements $< $@

$(BUILD_DIR)/codegen_expressions.o: src/codegen/expressions.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n codegen.expressions $< $@

$(BUILD_DIR)/main.o: src/main.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n main $< $@

$(BUILD_DIR)/generate.o: src/generate.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n generate $< $@

$(BUILD_DIR)/assemble.o: src/assemble.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n assemble $< $@

$(BUILD_DIR)/build.o: src/build.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n build $< $@

$(BUILD_DIR)/run.o: src/run.lua | $(BUILD_DIR)
	@echo "[LUAJIT] $< -> $@"
	@luajit -b -n run $< $@

# Generate main.h with bytecode sizes
$(MAIN_HEADER): $(BUILD_DIR)/main.o $(BUILD_DIR)/lexer_init.o $(BUILD_DIR)/parser_init.o \
                $(BUILD_DIR)/codegen_init.o $(BUILD_DIR)/codegen_types.o $(BUILD_DIR)/codegen_memory.o \
                $(BUILD_DIR)/codegen_functions.o $(BUILD_DIR)/codegen_statements.o $(BUILD_DIR)/codegen_expressions.o \
                $(BUILD_DIR)/generate.o $(BUILD_DIR)/assemble.o $(BUILD_DIR)/build.o $(BUILD_DIR)/run.o
	@echo -n "[NM] main.h"
	@echo "// Auto-generated" > $@
	@echo "#include <stddef.h>" >> $@
	@for obj in $^ ; do \
		name=$$(basename $$obj .o) ; \
		size=$$(nm -S $$obj | grep luaJIT_BC | awk '{print "0x" $$2}') ; \
		echo "const size_t luaJIT_BC_$${name}_size = $$size;" >> $@ ; \
		printf " $${size}" | sed 's/0x0\+/0x/' ; \
	done
	@echo

# Create static library
$(LIBRARY): $(BUILD_DIR)/main.o $(BUILD_DIR)/lexer_init.o $(BUILD_DIR)/parser_init.o \
            $(BUILD_DIR)/codegen_init.o $(BUILD_DIR)/codegen_types.o $(BUILD_DIR)/codegen_memory.o \
            $(BUILD_DIR)/codegen_functions.o $(BUILD_DIR)/codegen_statements.o $(BUILD_DIR)/codegen_expressions.o \
            $(BUILD_DIR)/generate.o $(BUILD_DIR)/assemble.o $(BUILD_DIR)/build.o $(BUILD_DIR)/run.o
	@echo "[AR] *.o -> $@"
	@ar crs $@ $^

# Copy main.c to build directory
$(C_SOURCE): src/main.c | $(BUILD_DIR)
	@cp $< $@

# Build the final binary
$(OUT): check-deps $(LIBRARY) $(MAIN_HEADER) $(C_SOURCE)
	@echo "[CC] main.c -lczar ..."
	@printf "\t%s\n" "$(CFLAGS)"
	@printf "\t%s\n" "$(LDFLAGS)"
	@cc $(CFLAGS) -o $@ $(C_SOURCE) $(LDFLAGS)
	@echo -n "[CZ] "
	@file -b $@
	@echo "[DEMO] Running demo..."
	@./$@ run ./demo/main.cz >/dev/null 2>/tmp/cz && echo "[DEMO] SUCCESS" || { echo "[DEMO] FAILURE" >&2 ; cat /tmp/cz ; exit 1 ; }
	@rm -f ./a.out

# Clean build artifacts
.PHONY: clean
clean:
	@echo "[CLEAN] Removing build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -vf *.o main.h *.a $(OUT) a.out
	@find ./tests -type f -name '*.c' -print -delete 2>/dev/null || true
	@find ./tests -type f -name '*.s' -print -delete 2>/dev/null || true
	@find ./tests -type f -executable -print -delete 2>/dev/null || true
	@find ./demo -type f -name '*.c' -print -delete 2>/dev/null || true
	@find ./demo -type f -name '*.s' -print -delete 2>/dev/null || true
	@find ./demo -type f -executable -print -delete 2>/dev/null || true

# Run tests (like check.sh)
.PHONY: test
test: $(OUT)
	@echo "[TEST] Running test suite..."
	@mkdir -p $(BUILD_DIR)
	@ok=0 ; \
	ko=0 ; \
	for f in tests/*.cz ; do \
		n=$$(basename $$f) ; \
		n=$${n%@*} ; \
		r=$${f##*@} ; \
		r=$${r%.*} ; \
		echo -n "- tests/$$n..." ; \
		case $$r in \
			''|*[!0-9]*) r=-1 ;; \
		esac ; \
		./$(OUT) build $$f -o $(BUILD_DIR)/$$n >/dev/null 2>/tmp/cz ; \
		if [ ! -x $(BUILD_DIR)/$$n ] ; then \
			echo " ERROR:" ; \
			cat /tmp/cz >&2 ; \
			ko=$$((ko + 1)) ; \
		else \
			$(BUILD_DIR)/$$n >/dev/null 2>/tmp/cz ; \
			e=$$? ; \
			if [ $$e -ne $$r ] ; then \
				echo " FAILURE: $$r vs $$e" ; \
				ko=$$((ko + 1)) ; \
			else \
				[ $$e -ne 134 ] && echo " SUCCESS: $$r" || true ; \
				ok=$$((ok + 1)) ; \
			fi ; \
			rm -f $(BUILD_DIR)/$$n ; \
		fi ; \
		rm -f /tmp/cz ; \
	done ; \
	echo "OK=$$ok KO=$$ko" ; \
	[ $$ko -gt 0 ] && rm -f ./$(OUT) || true ; \
	[ $$ko -eq 0 ] || exit $$ko

.PHONY: help
help:
	@echo "Czar Compiler Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make          Build the cz binary (default)"
	@echo "  make all      Build the cz binary"
	@echo "  make clean    Remove all build artifacts"
	@echo "  make test     Run the test suite"
	@echo "  make help     Show this help message"
