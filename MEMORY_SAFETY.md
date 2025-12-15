# Memory Safety Features

Czar implements compile-time memory safety checks to prevent common security vulnerabilities.

## Features

### 1. Pointer Arithmetic Prohibition

Pointer arithmetic is completely forbidden in Czar to prevent buffer overflows and out-of-bounds memory access.

**Forbidden operations:**
- `pointer + integer`
- `integer + pointer`
- `pointer - integer`
- `pointer - pointer`

**Example:**
```czar
i32* p = &x
i32* q = p + 1  // ERROR: Pointer arithmetic is forbidden
```

**Error message:**
```
Pointer arithmetic is forbidden. Cannot add pointer and numeric type. 
Czar enforces memory safety by disallowing pointer arithmetic operations.
```

### 2. Use-After-Free Detection

The compiler tracks when pointers are freed and detects attempts to use them afterwards.

**Example:**
```czar
Data* p = new Data { value: 42 }
free p
i32 x = p.value  // ERROR: Use-after-free detected
```

**Error message:**
```
Use-after-free detected: Variable 'p' is used after being freed. 
This is a memory safety violation.
```

### 3. Array Bounds Checking

For arrays with known sizes, the compiler performs compile-time bounds checking on constant indices.

**Syntax:**
```czar
i32[5] arr        // Declare array of 5 integers
mut i32[10] nums  // Mutable array of 10 integers
```

**Example:**
```czar
i32[5] arr
i32 x = arr[2]   // OK: index 2 is in bounds [0, 5)
i32 y = arr[10]  // ERROR: index 10 is out of bounds
```

**Error message:**
```
Array index out of bounds: index 10 is out of range [0, 5) for array of size 5. 
Czar enforces compile-time bounds checking for memory safety.
```

## Test Files

The following test files demonstrate the safety features:

**Safety violation tests (expected to fail at compile time):**
- `tests/pointer_arithmetic_forbidden.cz` - Demonstrates pointer arithmetic detection
- `tests/use_after_free_detection.cz` - Demonstrates use-after-free detection
- `tests/array_bounds_check.cz` - Demonstrates bounds checking

**Valid usage tests (should compile and run successfully):**
- `tests/valid_pointer_ops.cz` - Valid pointer operations (dereference, address-of)
- `tests/valid_free_usage.cz` - Proper memory management
- `tests/valid_array_access.cz` - Valid array access within bounds

## Implementation Details

### Pointer Arithmetic Detection
- Implemented in `src/typechecker/inference.lua` in the `infer_binary_type` function
- Checks binary operations for pointer + numeric combinations
- Rejects pointer arithmetic at type checking phase

### Use-After-Free Detection
- Implemented in `src/analysis/init.lua` 
- Tracks freed variables across scopes during lifetime analysis
- Detects when freed variables are used in expressions
- Runs after lowering and before code generation

### Array Bounds Checking
- Array types added to parser in `src/parser/init.lua`
- Type inference in `src/typechecker/inference.lua` checks constant indices
- Code generation support in `src/codegen/` modules
- Only checks constant indices at compile time (runtime bounds checking would require additional runtime support)

## Benefits

These compile-time safety checks help prevent:
- Buffer overflows
- Memory corruption
- Use-after-free vulnerabilities
- Out-of-bounds memory access
- Pointer arithmetic bugs

All checks are performed at compile time with zero runtime overhead.
