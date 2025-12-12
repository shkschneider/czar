# Named and Default Parameters

This document describes the named and default parameters feature for Czar functions.

## Syntax

### Default Parameters

Functions can specify default values for parameters:

```czar
fn add(i32 x = 10, i32 y = 20) -> i32 {
    return x + y
}
```

When calling a function with default parameters, you can omit arguments that have defaults:

```czar
i32 r1 = add()        // Uses defaults: 10 + 20 = 30
i32 r2 = add(5)       // x=5, y uses default 20: 5 + 20 = 25
i32 r3 = add(5, 15)   // Both specified: 5 + 15 = 20
```

### Named Arguments

Function calls can use named arguments to specify which parameter receives which value:

```czar
fn compute(i32 x, i32 y, i32 z) -> i32 {
    return x + y - z
}

i32 r1 = compute(x: 10, y: 20, z: 5)    // 10 + 20 - 5 = 25
i32 r2 = compute(z: 5, x: 10, y: 20)    // Order doesn't matter: 10 + 20 - 5 = 25
```

### Combining Both

Named arguments work seamlessly with default parameters:

```czar
fn add(i32 x = 10, i32 y = 20) -> i32 {
    return x + y
}

i32 r1 = add()           // 10 + 20 = 30 (all defaults)
i32 r2 = add(y: 30)      // 10 + 30 = 40 (x uses default, y specified)
i32 r3 = add(y: 30, x: 5) // 5 + 30 = 35 (both specified via named args)
```

You can also mix positional and named arguments:

```czar
fn compute(i32 a, i32 b = 5, i32 c = 10) -> i32 {
    return a + b * c
}

i32 r1 = compute(2)              // 2 + 5*10 = 52 (b and c use defaults)
i32 r2 = compute(2, c: 20)       // 2 + 5*20 = 102 (b uses default)
i32 r3 = compute(2, 3, c: 20)    // 2 + 3*20 = 62 (only c is named)
```

### Methods

Named and default parameters work with methods too:

```czar
struct Vec2 {
    i32 x
    i32 y
}

fn Vec2:add(i32 dx = 0, i32 dy = 0) -> void {
    self.x = self.x + dx
    self.y = self.y + dy
}

fn main() -> i32 {
    mut Vec2 v = Vec2 { x: 10, y: 20 }
    
    v:add()           // No change (both defaults are 0)
    v:add(dx: 5)      // x becomes 15, y unchanged
    v:add(dy: 10, dx: 5)  // x becomes 20, y becomes 30
    
    return v.y  // 30
}
```

## Rules

1. **Positional arguments come first**: When mixing positional and named arguments, all positional arguments must come before any named arguments.

2. **Default parameters can be anywhere**: Unlike some languages, Czar allows default parameters anywhere in the parameter list, not just at the end.

3. **Named arguments can be in any order**: When using named arguments, they can appear in any order.

4. **No duplicate arguments**: You cannot specify the same parameter both positionally and by name.

5. **All required parameters must be provided**: Parameters without default values must receive an argument (either positionally or by name).

## Implementation Details

The compiler handles named and default parameters by:

1. **Parser**: Recognizes `= expr` after parameter names in function definitions, and `name: expr` in function calls.

2. **Code Generator**: Uses the `resolve_arguments` function to:
   - Separate positional and named arguments
   - Match arguments to parameters in the correct order
   - Fill in default values for missing arguments
   - Generate error messages for missing required arguments

3. **C Code Generation**: The generated C code always uses positional arguments. Named arguments and defaults are resolved at compile time, resulting in efficient runtime code with no overhead.

## Examples

See the test files for comprehensive examples:
- `tests/default_params:30.cz` - Default parameters only
- `tests/named_params:42.cz` - Named parameters only  
- `tests/named_default_params:55.cz` - Combined usage
- `tests/default_named_edge_cases:43.cz` - Edge cases
- `tests/methods_default_named:40.cz` - Methods with both features
