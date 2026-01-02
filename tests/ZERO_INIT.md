# Zero-Initialization Enforcement

## Overview

CZar enforces mandatory zero-initialization of all local variables to prevent undefined behavior from uninitialized memory reads.

## Rule

All local variables declared within function scope MUST be explicitly initialized at declaration time.

## Examples

### ✅ Valid Code

```c
int main(void) {
    /* Scalar types with explicit initialization */
    u32 count = 0;
    i32 value = 0;
    f32 temperature = 0.0f;
    
    /* Arrays with {0} initialization */
    u8 buffer[256] = {0};
    i32 values[10] = {0};
    
    /* Structs with {0} initialization */
    struct Point p = {0};
    
    /* Pointers can be initialized to NULL */
    char *str = NULL;
    
    return 0;
}
```

### ❌ Invalid Code (Triggers CZar Error)

```c
int main(void) {
    /* ERROR: Uninitialized scalar */
    u32 count;
    
    /* ERROR: Uninitialized array */
    u8 buffer[256];
    
    /* ERROR: Uninitialized struct */
    struct Point p;
    
    return 0;
}
```

## Scope Rules

- **Function-local variables**: MUST be initialized
- **Struct/union/enum members**: Do NOT require initialization (this is normal C behavior)
- **Global variables**: Not currently enforced (globals are zero-initialized by default in C)
- **Function parameters**: Not applicable (initialized by caller)

## Rationale

Uninitialized variables are a common source of bugs and undefined behavior in C. By requiring explicit initialization:

1. **Safety**: Eliminates undefined behavior from reading uninitialized memory
2. **Clarity**: Makes initialization explicit and visible in the code
3. **Debugging**: Easier to debug issues when all variables start with known values
4. **Consistency**: Enforces consistent coding practices across the codebase

## Error Messages

When the transpiler encounters an uninitialized variable, it emits an error like:

```
CZar Error: my_var:42: Variable 'my_var' must be explicitly initialized. CZar requires zero-initialization: u32 my_var = 0;
```

The error includes:
- Variable name
- Line number
- Suggested fix with correct initialization syntax

## See Also

- Design principle: "forced initialization ; zero initialization removes a footgun, not control" (DESIGN.md)
- Roadmap: v0.4 includes "Mandatory zero-initialization of locals"
