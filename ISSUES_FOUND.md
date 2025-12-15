# Issues, Dead Code, and Inconsistencies Found

## 1. Code Duplication Issues

### Duplicate `read_file` function
- **Location**: `src/main.lua`, `src/generate.lua`, `src/assemble.lua`
- **Issue**: The same `read_file` utility function is duplicated in 3 different files
- **Impact**: Code maintenance burden, potential for inconsistencies
- **Recommendation**: Create a shared utility module or accept this as documented in main.lua

### Duplicate `shell_escape` function
- **Location**: `src/build.lua`, `src/run.lua`
- **Issue**: The same shell escaping function is duplicated
- **Recommendation**: Extract to a shared utilities module

### Duplicate `join` helper function
- **Location**: `src/codegen/init.lua`, `src/codegen/functions.lua`, `src/codegen/statements.lua`, `src/codegen/expressions.lua`
- **Issue**: Simple join function duplicated across codegen modules
- **Recommendation**: Use Lua's built-in `table.concat` directly or create shared helper

## 2. Dead Code / Placeholder Code

### `src/lowering/init.lua` - Mostly Empty
- **Issue**: The lowering pass is essentially a no-op placeholder
- **Current behavior**: Just returns the AST unchanged
- **Comments indicate intended features**:
  - Insert explicit address-of (&) and dereference (*) operations
  - Make implicit pointer conversions explicit
  - Canonicalize control flow structures
  - Expand syntactic sugar
- **Impact**: Missing optimization/transformation opportunity
- **Status**: Documented as incomplete

## 3. Merge Conflict in Documentation

### README.md merge conflict markers
- **Issue**: File contains unresolved merge conflict markers (`<<<<<<< HEAD`, `=======`, `>>>>>>>`)
- **Impact**: Unprofessional appearance, confusing for users
- **Status**: FIXED

## 4. Potential Unoptimized Code

### Global context pattern in codegen
- **Location**: All codegen modules use `_G.Codegen` global
- **Issue**: Uses global variable for context sharing between modules
- **Impact**: Could make testing harder, not idiomatic Lua
- **Note**: This might be intentional for simplicity, but reduces modularity

### Type checking error accumulation
- **Location**: `src/typechecker/inference.lua` and related files
- **Issue**: Errors are accumulated but processing continues even after errors
- **Impact**: Could lead to cascading errors that confuse users
- **Note**: This might be intentional to show all errors at once

## 5. Missing Error Handling

### No validation for duplicate struct definitions
- **Impact**: Could lead to confusing behavior if same struct defined twice

### No validation for duplicate function definitions
- **Impact**: Last definition wins without warning

### Limited validation for method name collisions
- **Impact**: May not catch all method overloading conflicts

## 6. Code Consistency Issues

### Inconsistent error message formatting
- **Issue**: Some error messages use different formats/styles
- **Example**: Some include line numbers, others don't; capitalization varies

### Mixed use of string formatting
- **Issue**: Some places use `string.format()`, others use string concatenation with `..`
- **Recommendation**: Standardize on `string.format()` for clarity

## 7. Feature Gaps / Incomplete Features

### Array literals not supported
- **Documented in**: MEMORY_SAFETY.md mentions "Arrays don't yet support initializer lists"
- **Impact**: Arrays can only be initialized element by element

### Limited compile-time bounds checking
- **Issue**: Only works for constant indices, not for variables
- **Note**: Documented limitation

### No multi-dimensional arrays
- **Note**: Future enhancement

### No for loops
- **Issue**: Only while loops are supported
- **Impact**: More verbose code for common iteration patterns

## 8. Test Coverage Gaps

### Limited negative test cases
- Only 5 ko (failing) tests vs 77 ok (passing) tests
- Many error conditions not explicitly tested

### Missing edge case tests
- No tests for numeric overflow/underflow
- No tests for very deep nesting
- No tests for maximum identifier lengths
- No tests for unicode in strings/comments
- Limited tests for complex type scenarios

## Summary

Most issues are either:
1. **Documented limitations** (lowering pass, array literals, compile-time bounds checking)
2. **Design choices** (global context, error accumulation, code duplication to avoid circular deps)
3. **Minor consistency issues** (formatting, duplication)

The codebase is generally well-structured for a toy language implementation. The main opportunities for improvement are:
- Adding comprehensive test coverage (especially failing/negative tests)
- Completing the lowering pass implementation
- Reducing code duplication where practical
- Standardizing error message formatting

## Bugs Found During Testing

The following tests in `tests/ko/` currently compile successfully but SHOULD fail:

1. **comparison_type_mismatch.cz** - Comparing i32 with bool is not caught
2. **missing_return.cz** - Missing return statement in non-void function not detected
3. **recursive_struct_direct.cz** - Recursive struct definition not caught (would cause infinite size)
4. **void_return_value.cz** - Void function returning a value is not caught
5. **division_by_zero.cz** - Division by zero literal not caught at compile time

These represent missing validation in the type checker and semantic analyzer.
