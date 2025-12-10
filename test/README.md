# Tests

This directory contains unit tests for the czar C extension library.

## Test Files

Each test file focuses on a specific module or feature:

- `array_test.c` - Tests for `cz_array.h` (singly-linked list array operations)
- `case_test.c` - Tests for `cz_case.h` (string case conversions)
- `list_test.c` - Tests for `cz_list.h` (doubly-linked list operations)
- `log_test.c` - Tests for `cz_log.h` (logging functionality)
- `map_test.c` - Tests for `cz_map.h` (key-value map data structure)
- `memory_test.c` - Tests for `cz_memory.h` (memory management helpers)
- `misc_test.c` - Tests for `cz_misc.h` (utility macros)
- `pair_test.c` - Tests for `cz_pair.h` (key-value pair data structure)
- `string_test.c` - Tests for `cz_string.h` (string utilities)
- `test_test.c` - Tests for `cz_test.h` (testing framework itself)
- `types_test.c` - Tests for `cz_types.h` (type definitions and constants)

## Running Tests

### Run all tests
```bash
make test
```

### Run a specific test
```bash
# Build a specific test
make test/map_test

# Run it
./test/map_test
```

### Build with make
```bash
# Build all tests (without running)
make test/array_test test/map_test test/string_test

# Clean all test binaries
make clean
```
```

## Test Structure

Each test file follows this pattern:

```c
#include <stdio.h>
#include <assert.h>

#include "../cz_module.h"
#include "../cz_test.h"

int main(void) {
    // Test 1: Basic functionality
    // ... test code ...
    assert(condition);
    
    // Test 2: Edge cases
    // ... test code ...
    
    // Test 3: Error handling
    // ... test code ...
    
    return 0;
}
```

## Writing New Tests

1. Create a new file named `feature_test.c`
2. Include the relevant headers from the parent directory using `../`
3. Write test cases using `assert()` for conditions
4. Use `TEST()` macro for value comparisons (when appropriate)
5. Return 0 on success
6. The Makefile will automatically discover and compile your test
7. Run `make test` to build and execute all tests

## Test Conventions

- Use descriptive test names
- Test normal cases first, then edge cases
- Test error conditions when applicable
- Clean up allocated memory (though tests are short-lived)
- Use `assert()` for critical conditions
- Use `TEST()` macro for comparing values with helpful error messages
