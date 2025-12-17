# Comprehensive Modularization Test

This directory contains a comprehensive test of the Czar module system with multiple modules demonstrating various features.

## Key Feature: No Function Ordering Required

With forward declarations automatically generated in the C output, functions can call other functions defined anywhere in the file, regardless of order. This eliminates the C limitation where functions must be declared before use.

## Structure

```
app/
├── main.cz      - Main application (imports and uses other modules)
├── math.cz      - Math operations module
├── geometry.cz  - Geometry shapes and calculations module
├── utils.cz     - Utility functions module
└── README.md    - This file
```

## Modules

### app.main
The main application module that imports and uses all other modules.

**Features demonstrated:**
- Module declaration
- Multiple imports (commented for future multi-file support)
- Unused import warning (`import app.unused`)
- Using public functions from inline implementations
- **Functions calling other functions defined later in the file**

### app.math
Math operations module with basic arithmetic.

**Public exports:**
- `add(i32, i32) -> i32` - Add two numbers
- `multiply(i32, i32) -> i32` - Multiply two numbers
- `sum_of_squares(i32, i32) -> i32` - Sum of squares (calls `internal_square` defined later)

**Private functions:**
- `internal_square(i32) -> i32` - Internal helper (not exported, defined after use)

### app.geometry
Geometry module with shapes and calculations.

**Public exports:**
- `Point` struct - 2D point
- `Rectangle` struct - Rectangle with top-left point, width, height
- `create_point(i32, i32) -> Point` - Create a point
- `calculate_area(Rectangle) -> i32` - Calculate area (calls `get_width` defined later)
- `calculate_perimeter(Rectangle) -> i32` - Calculate perimeter

**Private types:**
- `InternalBuffer` struct - Internal data structure (not exported)

**Private functions:**
- `get_width(Rectangle) -> i32` - Internal helper (not exported, defined after use)

### app.utils
Utility functions module.

**Public exports:**
- `abs(i32) -> i32` - Absolute value
- `max(i32, i32) -> i32` - Maximum of two numbers
- `min(i32, i32) -> i32` - Minimum of two numbers
- `clamp(i32) -> i32` - Clamp value (calls `clamp_value` defined later)

**Private functions:**
- `clamp_value(i32, i32, i32) -> i32` - Internal helper (not exported, defined after use)

## Features Tested

1. **Module declarations** - Each file declares its module namespace
2. **Public visibility** - Functions and structs marked with `pub`
3. **Private visibility** - Unmarked functions/structs are module-private
4. **Import statements** - Standard imports and imports with aliases
5. **Unused import warnings** - `import app.unused` triggers warning
6. **Forward declarations** - Functions can be defined in any order
7. **No manual ordering required** - Helper functions can be defined after use

## Forward Declarations

The compiler automatically generates forward declarations for all functions at the top of the C file, eliminating the C limitation where functions must be declared before use. This means you can organize your Czar code logically without worrying about declaration order.

**Example:**
```czar
// This works! main calls compute_value which is defined later
fn main() i32 {
    return compute_value(10)
}

// compute_value is defined after main
fn compute_value(i32 x) i32 {
    return x * 2
}
```

## Running

Compile and run the main test:

```bash
./cz build tests/ok/app/main.cz -o app_test
./app_test
```

Each module file can also be compiled individually:

```bash
./cz compile tests/ok/app/math.cz
./cz compile tests/ok/app/geometry.cz
./cz compile tests/ok/app/utils.cz
```

## Expected Warnings

When compiling `main.cz`, you should see:
- Warning about unused import `app.unused`
- Warning about unused variable `p2` (intentional for demonstration)

## Notes

This test demonstrates:
1. The foundation for the module system with syntax ready for future multi-file support
2. The automatic generation of forward declarations, eliminating C function ordering issues
3. How private helper functions can be defined after their use without manual reordering
