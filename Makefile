.PHONY: all clean test install

# Compiler paths
CC = cc

# Find all test .cz files
TEST_FILES = $(wildcard tests/test_*.cz)
EXPECTED_RESULTS = \
	test_types:42 \
	test_bindings:30 \
	test_structs:15 \
	test_pointers:30 \
	test_functions:19 \
	test_arithmetic:53 \
	test_comparison:1 \
	test_if_else:50 \
	test_while:55 \
	test_comments:60 \
	test_no_semicolons:15

# Default target: compile and run example
all:
	./cz ./example.cz
	./a.out
	rm -f ./a.out

# Run the test suite
test: $(TEST_FILES)
	@echo "Running all tests..."
	@passed=0; failed=0; \
	for test in $(TEST_FILES); do \
		name=$$(basename $$test .cz); \
		echo "Testing $$name..."; \
		./cz $$test -o tests/$$name 2>&1 | grep -v "Successfully"; \
		if [ $$? -ne 0 ] && [ ! -f tests/$$name ]; then \
			echo "  FAIL: Compilation failed"; \
			failed=$$((failed + 1)); \
			continue; \
		fi; \
		tests/$$name; \
		exit_code=$$?; \
		expected=$$(echo "$(EXPECTED_RESULTS)" | tr ' ' '\n' | grep "^$$name:" | cut -d: -f2); \
		if [ -n "$$expected" ]; then \
			if [ $$exit_code -eq $$expected ]; then \
				echo "  PASS (exit code: $$exit_code)"; \
				passed=$$((passed + 1)); \
			else \
				echo "  FAIL: Expected exit code $$expected, got $$exit_code"; \
				failed=$$((failed + 1)); \
			fi; \
		else \
			echo "  PASS (exit code: $$exit_code, no expected value)"; \
			passed=$$((passed + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "Results: $$passed passed, $$failed failed"; \
	if [ $$failed -gt 0 ]; then exit 1; fi

# Clean build artifacts
clean:
	rm -f ./example.c ./a.out ./my_program
	rm -f tests/*.c tests/test_types tests/test_bindings tests/test_structs tests/test_pointers \
		tests/test_functions tests/test_arithmetic tests/test_comparison tests/test_if_else \
		tests/test_while tests/test_comments tests/test_no_semicolons

# Install the cz compiler (requires root/sudo for system-wide install)
install:
	@echo "Installing cz to /usr/local/bin/cz"
	@echo "You may need to run this with sudo"
	install -m 755 cz /usr/local/bin/cz
	@echo "Installation complete. You can now use 'cz' from anywhere."
