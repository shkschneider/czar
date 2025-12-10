# Makefile for testing Czar compiler v0 features

# Compiler paths
CZAR = cd .. && lua main.lua
CC = cc

# Find all test .cz files
TESTS = $(wildcard test_*.cz)
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

.PHONY: all clean test

all: test

test: $(TESTS)
	@echo "Running all tests..."
	@passed=0; failed=0; \
	for test in $(TESTS); do \
		name=$${test%.cz}; \
		echo "Testing $$name..."; \
		(cd .. && lua main.lua tests/$$test) > $$name.c 2>&1; \
		if [ $$? -ne 0 ]; then \
			echo "  FAIL: Compilation failed"; \
			cat $$name.c; \
			failed=$$((failed + 1)); \
			continue; \
		fi; \
		$(CC) $$name.c -o $$name 2>&1; \
		if [ $$? -ne 0 ]; then \
			echo "  FAIL: C compilation failed"; \
			failed=$$((failed + 1)); \
			continue; \
		fi; \
		./$$name; \
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

clean:
	rm -f *.c *.out test_types test_bindings test_structs test_pointers \
		test_functions test_arithmetic test_comparison test_if_else \
		test_while test_comments test_no_semicolons
