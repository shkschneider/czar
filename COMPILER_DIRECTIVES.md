# Compiler Directives

This document describes compiler directives that can be used to customize the behavior of the Czar compiler. Directives are special commands that begin with `#` and provide instructions to the compiler rather than being part of the program logic.

## Planned Directives

### Memory Management Directives

#### `#malloc <function_name>`

Specifies a custom allocation function to replace the default C `malloc`.

**Syntax:**
```czar
#malloc cz_malloc
```

**Purpose:**
- Allows users to provide custom memory allocators
- Useful for testing, debugging, or specialized memory management strategies
- Enables integration with custom memory pools, arena allocators, or tracking allocators

**Requirements:**
- The specified function must have the signature: `void* function_name(size_t size)`
- The function must be available at link time (either defined in the Czar code or linked from C)
- Must be declared before any memory allocations occur in the code

**Example:**
```czar
// Define or declare custom allocator
extern fn cz_malloc(u64 size) -> void*

// Tell compiler to use it instead of malloc
#malloc cz_malloc

struct Vec2 {
    i32 x
    i32 y
}

fn main() -> i32 {
    // This will use cz_malloc instead of malloc
    Vec2 v = new Vec2 { x: 10, y: 20 }
    return 0
}
```

#### `#free <function_name>`

Specifies a custom deallocation function to replace the default C `free`.

**Syntax:**
```czar
#free cz_free
```

**Purpose:**
- Pairs with `#malloc` to provide complete custom memory management
- Ensures allocations and deallocations use matching allocator/deallocator pairs
- Enables custom cleanup logic, tracking, or validation

**Requirements:**
- The specified function must have the signature: `void function_name(void* ptr)`
- The function must be available at link time
- Should be used in conjunction with `#malloc` to ensure matching allocator/deallocator

**Example:**
```czar
// Define or declare custom deallocator
extern fn cz_free(void* ptr) -> void

// Tell compiler to use custom memory management
#malloc cz_malloc
#free cz_free

fn main() -> i32 {
    // Allocations use cz_malloc, deallocations use cz_free
    Vec2 v = new Vec2 { x: 10, y: 20 }
    // Automatic cleanup uses cz_free
    return 0
}
```

## Implementation Strategy

### Parsing Phase
1. Lexer recognizes `#` as a directive marker
2. Parser identifies directive type and arguments
3. Directives are processed before code generation

### Code Generation Phase
1. Compiler maintains a table of custom function mappings
2. When generating memory allocation code:
   - Check if `#malloc` directive was specified
   - Use custom function if available, otherwise use default `malloc`
3. When generating deallocation code:
   - Check if `#free` directive was specified
   - Use custom function if available, otherwise use default `free`

### Validation
- Compiler validates that directive appears before code that would use it
- Type checking ensures function signatures match requirements
- Link-time errors if specified functions are not available

## Use Cases

### 1. Custom Memory Tracking
```czar
#malloc tracked_malloc
#free tracked_free

// All allocations/deallocations are tracked
```

### 2. Arena Allocators
```czar
#malloc arena_alloc
#free arena_free  // No-op or arena cleanup

// Fast bulk allocations, cleanup entire arena at once
```

### 3. Testing and Debugging
```czar
#malloc debug_malloc
#free debug_free

// Allocators that check for corruption, log calls, etc.
```

### 4. Platform-Specific Allocators
```czar
#malloc platform_malloc
#free platform_free

// Use platform-specific memory management (e.g., embedded systems)
```

## Future Extensions

### Potential Additional Directives

- `#realloc <function_name>` - Custom reallocation (if/when realloc is needed)
- `#allocator { malloc = ..., free = ..., realloc = ... }` - Bundle directive
- `#malloc_align <function_name>` - Aligned allocations
- `#malloc_scope <scope>` - Different allocators for different scopes

### Scope Considerations

Directives could potentially be scoped:
- **Global scope**: Applies to entire file
- **Function scope**: Applies only within a function
- **Block scope**: Applies within a specific block

Example:
```czar
fn main() -> i32 {
    #malloc arena_alloc
    #free arena_free
    
    // These use arena allocator
    Vec2 v1 = new Vec2 { x: 1, y: 2 }
    Vec2 v2 = new Vec2 { x: 3, y: 4 }
    
    return 0
}

fn other() -> i32 {
    // This uses default malloc
    Vec2 v = new Vec2 { x: 5, y: 6 }
    return 0
}
```

## Notes

- Directives are compile-time only and have zero runtime overhead
- They modify code generation, not runtime behavior
- Multiple directives of the same type replace previous ones
- Directives follow lexical scope rules
- The `--debug` flag is orthogonal to custom allocators and works with both default and custom allocators
