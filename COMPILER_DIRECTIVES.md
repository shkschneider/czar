# Compiler Directives

This document describes compiler directives that can be used to customize the behavior of the Czar compiler. Directives are special commands that begin with `#` and provide instructions to the compiler rather than being part of the program logic.

## Implemented Directives

### Compile-Time Information Directives

These directives are replaced at compile time with values that provide information about the compilation context. They can be used in any expression context.

#### `#FILE`

Returns the source filename as a string literal.

**Syntax:**
```czar
#FILE
```

**Type:** `string` (const char* in generated C)

**Purpose:**
- Provides the name of the source file being compiled
- Useful for logging, debugging, and error reporting
- Returns just the filename (e.g., "main.cz"), not the full path

**Example:**
```czar
fn main() -> i32 {
    // Log which file is being executed
    // In a real implementation with print support:
    // print("Running file: ", #FILE)
    return 0
}
```

#### `#FUNCTION`

Returns the current function name as a string literal.

**Syntax:**
```czar
#FUNCTION
```

**Type:** `string` (const char* in generated C)

**Purpose:**
- Provides the name of the function where the directive is used
- Useful for logging, debugging, and tracing execution
- Returns "unknown" if used outside a function context

**Example:**
```czar
fn calculate(i32 x) -> i32 {
    // Log the function name for debugging
    // In a real implementation with print support:
    // print("Entering function: ", #FUNCTION)
    return x * 2
}

fn main() -> i32 {
    i32 result = calculate(21)
    return result
}
```

#### `#DEBUG`

Returns a boolean indicating whether debug mode is enabled.

**Syntax:**
```czar
#DEBUG
```

**Type:** `bool`

**Values:**
- `false` - default, when compiling without `--debug` flag
- `true` - when compiling with `--debug` flag

**Purpose:**
- Enables conditional compilation of debug-only code
- Avoids runtime overhead for debug checks in production builds
- Works seamlessly with if statements and other control flow

**Example:**
```czar
fn process_data(i32 value) -> i32 {
    bool debug = #DEBUG
    
    if debug {
        // This code only runs when compiled with --debug
        // In a real implementation with print support:
        // print("Debug: processing value ", value)
    }
    
    return value * 2
}

fn main() -> i32 {
    return process_data(21)
}
```

**Usage with compiler:**
```bash
# Compile without debug mode (#DEBUG = false)
cz build program.cz -o program

# Compile with debug mode (#DEBUG = true)
cz build program.cz --debug -o program_debug

# Run with debug mode
cz run program.cz --debug
```

### Why No `#LINE` Directive?

The `#LINE` directive was considered but not implemented to avoid overhead. Line number information is already tracked by the lexer and available in error messages. Adding a runtime-accessible line number would require additional bookkeeping and code generation that doesn't provide enough value for the added complexity.

## Memory Management Directives

### `#malloc <function_name>`

Specifies a custom allocation function to replace the default C `malloc`.

**Status:** ✅ Implemented

**Syntax:**
```czar
#malloc cz_malloc
```

**Purpose:**
- Allows users to provide custom memory allocators
- Useful for testing, debugging, or specialized memory management strategies
- Enables integration with custom memory pools, arena allocators, or tracking allocators

**Requirements:**
- Must be a top-level directive (before any functions or structs)
- The specified function must have the signature: `void* function_name(size_t size)` or `void* function_name(size_t size, int is_explicit)` for debug wrappers
- The function must be available at link time (either defined in the Czar code or linked from C)

**Debug Mode Behavior:**
When compiling with `--debug` flag, the compiler automatically uses `cz_malloc` (the built-in debug memory tracker) unless explicitly overridden with a directive.

**Reset to Standard C:**
Use `#malloc malloc` to explicitly use standard C `malloc`, even in debug mode.

**Example:**
```czar
// Use custom allocator
#malloc my_custom_malloc

struct Vec2 {
    i32 x
    i32 y
}

fn main() -> i32 {
    // This will use my_custom_malloc instead of malloc
    Vec2 v = new Vec2 { x: 10, y: 20 }
    return 0
}
```

**Example - Reset to standard C:**
```czar
// Even in debug mode, use standard malloc
#malloc malloc
#free free

fn main() -> i32 {
    // Uses standard malloc/free
    return 0
}
```

### `#free <function_name>`

Specifies a custom deallocation function to replace the default C `free`.

**Status:** ✅ Implemented

**Syntax:**
```czar
#free cz_free
```

**Purpose:**
- Pairs with `#malloc` to provide complete custom memory management
- Ensures allocations and deallocations use matching allocator/deallocator pairs
- Enables custom cleanup logic, tracking, or validation

**Requirements:**
- Must be a top-level directive (before any functions or structs)
- The specified function must have the signature: `void function_name(void* ptr)` or `void function_name(void* ptr, int is_explicit)` for debug wrappers
- Should be used in conjunction with `#malloc` to ensure matching allocator/deallocator

**Debug Mode Behavior:**
When compiling with `--debug` flag, the compiler automatically uses `cz_free` (the built-in debug memory tracker) unless explicitly overridden with a directive.

**Reset to Standard C:**
Use `#free free` to explicitly use standard C `free`, even in debug mode.

**Example:**
```czar
// Use custom memory management
#malloc my_custom_malloc
#free my_custom_free

fn main() -> i32 {
    // Allocations use my_custom_malloc, deallocations use my_custom_free
    Vec2 v = new Vec2 { x: 10, y: 20 }
    return 0
}
```

## Implementation

### Parsing Phase
1. Lexer recognizes `#` as a directive marker
2. Parser identifies directive type and arguments at top-level
3. Directives are processed before code generation

### Code Generation Phase
1. Compiler maintains custom_malloc and custom_free names
2. In debug mode, automatically sets to cz_malloc/cz_free if not overridden
3. When generating memory allocation code:
   - Use custom_malloc if set, otherwise use default `malloc`
   - Special handling for `cz_malloc` which takes an is_explicit flag
4. When generating deallocation code:
   - Use custom_free if set, otherwise use default `free`
   - Special handling for `cz_free` which takes an is_explicit flag

### Debug Memory Tracking

The built-in `cz_malloc` and `cz_free` functions track:
- Explicit allocations (via `new` keyword)
- Implicit allocations (compiler-generated)
- Peak memory usage
- Memory leaks

## Use Cases

### 1. Automatic Debug Memory Tracking
```czar
// No directives needed - automatic in debug mode
fn main() -> i32 {
    // Compile with --debug to get memory statistics
    Vec2 v = new Vec2 { x: 10, y: 20 }
    return 0
}
```

Compile with `cz build program.cz --debug` to automatically track all memory allocations.

### 2. Custom Memory Tracking
```czar
#malloc tracked_malloc
#free tracked_free

// All allocations/deallocations use custom trackers
```

### 3. Arena Allocators
```czar
#malloc arena_alloc
#free arena_free  // No-op or arena cleanup

// Fast bulk allocations, cleanup entire arena at once
```

### 4. Testing and Debugging with Standard Allocators
```czar
#malloc malloc
#free free

// Override debug mode to use standard C allocators
```

### 5. Platform-Specific Allocators
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
