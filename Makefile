# CZar Makefile
# Build system for CZar C semantic authority layer

CC = cc
CFLAGS = -std=c11 -Wall -Wextra -pedantic -O2
LDFLAGS =

# Directories
SRC_DIR = src
BIN_DIR = bin
TEST_DIR = tests
BUILD_DIR = build

# Tool binary
CZ = $(BUILD_DIR)/cz

# Default target
.PHONY: all
all: $(CZ)

# Build the cz tool
$(CZ): $(BIN_DIR)/main.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Process a .cz file through the full pipeline
# Usage: make process FILE=tests/example.cz
# This will create tests/example.pp.cz, tests/example.app.c, and tests/example.out (binary)
.PHONY: process
process:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE not specified. Usage: make process FILE=tests/example.cz"; \
		exit 1; \
	fi
	@echo "Processing $(FILE) through CZar pipeline..."
	@$(MAKE) $(basename $(FILE)).out

# Pattern rule: .cz -> .pp.cz (preprocess with cc -E)
%.pp.cz: %.cz
	@echo "Preprocessing $< -> $@"
	$(CC) -E -P -x c $< -o $@

# Pattern rule: .pp.cz -> .app.c (process with cz tool)
%.app.c: %.pp.cz $(CZ)
	@echo "Processing $< -> $@"
	$(CZ) $< $@

# Keep intermediate files
.PRECIOUS: %.pp.cz %.app.c

# Pattern rule: .app.c -> .out binary (compile normally)
%.out: %.app.c
	@echo "Compiling $< -> $@"
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -f *.pp.cz *.app.c *.out *.o
	rm -f $(TEST_DIR)/*.pp.cz $(TEST_DIR)/*.app.c $(TEST_DIR)/*.out $(TEST_DIR)/*.o

# Clean everything including binaries from processed files
.PHONY: distclean
distclean: clean
	@find . -type f -executable -not -path "./.git/*" -exec rm -f {} \; 2>/dev/null || true

# Help target
.PHONY: help
help:
	@echo "CZar Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all              Build the cz tool (default)"
	@echo "  clean            Remove build artifacts"
	@echo "  distclean        Remove all generated files"
	@echo "  process FILE=x   Process a .cz file through the full pipeline (e.g., make process FILE=tests/hello.cz)"
	@echo ""
	@echo "Pipeline:"
	@echo "  .cz -> (cc -E) -> .pp.cz -> (cz) -> .app.c -> (cc) -> .out binary"
