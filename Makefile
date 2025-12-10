# Makefile for czar C extension library

# Compiler and flags
CC = cc
CFLAGS = -std=c2x -I . -W -Werror -Wall -Wstrict-prototypes -g -funroll-loops -O3
LDFLAGS = -lc -lm -static

# Output binaries
OUT = demo

# Test files
TEST_DIR = test
TEST_SOURCES = $(wildcard $(TEST_DIR)/*_test.c)
TEST_BINS = $(TEST_SOURCES:.c=)

# Phony targets
.PHONY: all clean test help

# Default target
all:
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(OUT) demo.c
	./$(OUT)
	@rm -f ./$(OUT)

# Help message
help:
	@echo "Czar -- C extension library:"
	@echo "  make [all]    - Build demo program"
	@echo "  make test     - Build and run all tests"
	@echo "  make clean    - Remove all build artifacts"
	@echo "  make help     - Show this help message"

# Test target - build and run all tests
test: $(TEST_BINS)
	@echo "Running tests from $(TEST_DIR)/ directory..."
	@for test in $(TEST_BINS); do \
		echo "  $$(basename $$test)..."; \
		./$$test && rm -f ./$$test || exit 1; \
	done
	@echo "All tests passed!"

# Pattern rule for building test binaries
$(TEST_DIR)/%_test: $(TEST_DIR)/%_test.c cz*.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

# Clean target
clean:
	rm -f $(MAIN_BIN) $(OUT)
	@echo "Cleaned all build artifacts"

# EOF
