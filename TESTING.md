# Testing Guide

This document provides guidelines for writing and maintaining tests for the Czar language compiler.

## Test Philosophy

- **Comprehensive Coverage**: Test all language features, both success and failure cases
- **Minimal Tests**: Each test should focus on a specific feature or behavior
- **Clear Intent**: Test names and comments should make the purpose obvious
- **Fast Execution**: Tests should run quickly to enable rapid iteration

## Test Types

### 1. Positive Tests (`tests/ok/`)

These tests verify that valid code compiles and runs correctly.

**Example**:
```czar
// Test basic arithmetic operations
fn main() i32 {
    i32 a = 10
    i32 b = 20
    i32 sum = a + b
    
    if sum == 30 {
        return 0  // success
    }
    return 1  // failure
}
```

### 2. Negative Tests (`tests/ko/`)

These tests verify that invalid code is properly rejected.

**Example**:
```czar
// Test that assigning to immutable variable fails
fn main() i32 {
    i32 x = 10
    x = 20  // ERROR: cannot assign to immutable variable
    return 0
}
```

### 3. Work-in-Progress Tests (`tests/fail/`)

These tests document features that are planned but not yet implemented, or edge cases that need attention.

## Writing Good Tests

### Naming

- Use descriptive names: `string_interpolation_basic.cz`
- Suffixes: `_basic`, `_comprehensive`, `_edge_cases`
- Prefix error tests with the error type: `type_mismatch_assignment.cz`

### Structure

```czar
// Clear description of what this test validates
// Multiple lines if needed to explain context

fn helper_function() i32 {
    // Helper functions if needed
    return 0
}

fn main() i32 {
    // Setup
    i32 value = 42
    
    // Test the feature
    i32 result = helper_function()
    
    // Verify result
    if result == 0 {
        return 0  // success
    }
    return 1  // failure
}
```

### Best Practices

1. **One Concept Per Test**: Test one feature or one error condition
2. **Self-Contained**: Don't rely on external state or files (unless testing imports)
3. **Deterministic**: Always produce the same result
4. **Commented**: Explain what's being tested and why
5. **Return Codes**: Use 0 for success, non-zero for failure
6. **Meaningful Assertions**: Check actual behavior, not just compilation

## Testing Specific Features

### Memory Management

```czar
// Test heap allocation and deallocation
fn main() i32 {
    Person? p = new Person { age: 25 }
    #defer free p
    
    if p.age == 25 {
        return 0
    }
    return 1
}
```

### Error Conditions

```czar
// Test array bounds checking
fn main() i32 {
    i32[5] arr = [1, 2, 3, 4, 5]
    i32 x = arr[10]  // ERROR: out of bounds
    return 0
}
```

### Multi-File Tests

For tests requiring multiple files, create a subdirectory:
```
tests/ok/app/myapp/
  main.cz
  utils.cz
  README.md
```

## Running Tests

### During Development

```bash
# Run just your new test
./check.sh tests/ok/my_new_test.cz

# Run tests for a specific feature
./check.sh tests/ok/string*.cz
```

### Before Committing

```bash
# Run the full test suite
./check.sh

# Ensure all tests pass
# 305/305 SUCCESS expected
```

## Test Coverage Goals

Aim to test:
- ✅ Happy path (normal usage)
- ✅ Edge cases (empty, null, boundary values)
- ✅ Error conditions (type errors, null checks, bounds)
- ✅ Interaction between features
- ✅ Performance characteristics (for critical paths)

## Debugging Failed Tests

1. **Run the test directly**:
   ```bash
   ./dist/cz build tests/ok/mytest.cz -o test.out
   ./test.out
   echo $?  # Check exit code
   ```

2. **Examine generated C code**:
   ```bash
   ./dist/cz compile tests/ok/mytest.cz
   cat tests/ok/mytest.c
   ```

3. **Enable debug mode**:
   ```bash
   ./dist/cz build tests/ok/mytest.cz -o test.out --debug
   ./test.out
   ```

4. **Check compiler output**:
   ```bash
   ./dist/cz build tests/ok/mytest.cz -o test.out 2>&1 | less
   ```

## Adding Test Categories

When adding a new language feature:

1. Create basic test: `feature_basic.cz`
2. Create comprehensive test: `feature_comprehensive.cz`
3. Create error tests in `ko/`: `feature_error_condition.cz`
4. Update test count in `tests/README.md`
5. Document the feature in `FEATURES.md`

## Test Maintenance

- **Regular Review**: Periodically review tests for relevance
- **Keep Updated**: Update tests when language features change
- **Clean Artifacts**: Generated `.c` and `.out` files are gitignored
- **Document Changes**: Update this guide when testing practices evolve

## CI Integration

Tests run automatically on:
- Push to main branch
- Pull requests
- Manual workflow dispatch

See `.github/workflows/tests.yml` for configuration.

## Performance Testing

For performance-sensitive features, consider:
- Time complexity tests
- Memory usage validation
- Benchmark comparisons

## Future Improvements

- [ ] Code coverage reporting
- [ ] Mutation testing
- [ ] Fuzz testing framework
- [ ] Performance regression testing
- [ ] Integration test framework
