# Test Suite Documentation

This directory contains the test suite for the Czar language compiler.

## Test Organization

### Directory Structure

- `ok/` - Tests expected to compile and run successfully (exit code 0)
- `ko/` - Tests expected to fail compilation or exit with non-zero code
- `fail/` - Tests for features not yet implemented or edge cases

### Test Categories in `ok/`

#### Core Language Features
- Arithmetic operations and operators
- Control flow (if/else, while, for, loops)
- Functions and methods
- Types and type checking
- Variables and scoping

#### Advanced Features
- Anonymous functions and structs
- Generics (primitive generics)
- Interfaces (iface)
- Enums
- Varargs

#### Memory Management
- Stack vs heap allocation
- `new` and `free` operations
- Arena allocator
- `#defer` directive
- Pointer safety (safe vs unsafe)

#### Builtin Types
- Primitives: `i8/16/32/64`, `u8/16/32/64`, `f32/64`, `bool`
- Collections: `array<T>`, `pair<T:T>`, `map<T:T>`
- String operations and methods
- `any` type

#### Modularity
- Module system (`#module`)
- Import statements (`#import`)
- Visibility (`pub`, `prv`)

#### Macros and Directives
- `#assert`, `#log`, `#TODO`, `#FIXME`
- `#FILE`, `#LINE`, `#FUNCTION`
- `#DEBUG`
- `#defer`
- `#unsafe` (C interop)
- `#alloc` directive

#### Other Features
- Named and default parameters
- Operator overloading
- Type casting and `!!` operator
- Null handling (`?`, `??`)
- Mutability (`mut`)
- Destructors (`init`, `fini`)

### Test Categories in `ko/`

Tests for error conditions that should be caught by the compiler or runtime:
- Type mismatches
- Undefined variables/functions
- Access violations (private members)
- Array bounds checking
- Null pointer handling
- Invalid operations
- Duplicate declarations
- Missing required elements

### Test Naming Conventions

Test files should be named descriptively:
- `feature_basic.cz` - Basic usage of a feature
- `feature_comprehensive.cz` - Comprehensive test covering multiple aspects
- `feature_edge_cases.cz` - Edge cases and corner cases
- `error_condition.cz` - Specific error that should be caught (in `ko/`)

## Running Tests

### Run All Tests
```bash
./check.sh
```

### Run Specific Tests
```bash
./check.sh tests/ok/arithmetic.cz
./check.sh tests/ko/*.cz
```

### Run Test Categories
```bash
./check.sh tests/ok/string*.cz
./check.sh tests/ok/array*.cz
```

## Test Execution

The `check.sh` script:
1. Builds the compiler (`./build.sh`)
2. For each test:
   - In `ok/`: Compiles and runs, expects exit code 0
   - In `ko/`: Expects compilation failure or non-zero exit
3. Reports success/failure counts
4. Cleans up generated artifacts

## Writing New Tests

### Structure of a Test

```czar
// Brief description of what this test validates
fn main() i32 {
    // Test code here
    return 0  // 0 for success
}
```

### For `ok/` Tests
- Should compile successfully
- Should run and return 0
- Include comments explaining what's being tested
- Test one feature or a logical group of related features

### For `ko/` Tests
- Should fail to compile, OR
- Should compile but fail at runtime with non-zero exit
- Include comments explaining what error should be caught
- Test specific error conditions

## Test Coverage

Current statistics:
- Total tests: 305
- OK tests: 227
- KO tests: 77
- Fail tests: 12 (features not yet implemented)

## Generated Artifacts

Tests generate intermediate files:
- `*.c` - Generated C code
- `*.out` - Compiled executables
- These are cleaned automatically and gitignored

## Integration Tests

For multi-file projects, see `tests/ok/app/` which contains:
- Multi-module applications
- Import/export testing
- Real-world usage scenarios
