# Language Changes Summary

## Overview

This PR implements two major language enhancements to the Czar compiler:

1. **Heap Allocation with `new` Keyword**: Automatic memory management with scope-based cleanup
2. **let/mut Syntax**: Explicit `let` (immutable) and `mut` (mutable) keywords

## 1. Heap Allocation with `new` Keyword

### Syntax

```czar
// Allocate on heap
let p: *Point = new Point { x: 10, y: 20 }

// Use the pointer
let result: i32 = p.x + p.y

// p is automatically freed at scope exit
```

### Features

- **Automatic Cleanup**: Memory is automatically freed when the variable goes out of scope
- **Nested Scopes**: Works correctly with if/else blocks, while loops, and function blocks
- **All Exit Paths**: Cleanup happens both at explicit returns and block fallthrough
- **Initialization Support**: Can initialize struct fields inline with the allocation

### Implementation Details

- Generates `malloc(sizeof(Type))` for allocation
- Tracks heap-allocated variables per scope
- Inserts `free()` calls before returns and at end of blocks
- Uses GNU C statement expressions for initialization (requires GCC/Clang)

### Example

```czar
struct Data {
    value: i32
}

fn main() -> i32 {
    mut x: i32 = 10
    
    if x > 5 {
        // Allocate in nested scope
        let d: *Data = new Data { value: 20 }
        x = d.value
        // d is automatically freed here
    }
    
    return x  // returns 20
}
```

## 2. let/mut Syntax

### Old Syntax (Removed)

```czar
val x: i32 = 10      // immutable
var y: i32 = 20      // mutable
```

### New Syntax

```czar
let x: i32 = 10      // immutable
mut y: i32 = 20      // mutable
```

### Function Parameters

```czar
// Immutable parameter (default)
fn add(a: i32, b: i32) -> i32 {
    return a + b
}

// Mutable parameter
fn increment(mut c: *Counter) -> void {
    c.value = c.value + 1
}
```

### Benefits

- **Clearer Intent**: Both immutable and mutable are explicit with keywords
- **No Ambiguity**: Always clear whether a variable is `let` or `mut`
- **Familiar**: Similar to Rust's syntax
- **Consistent**: Same keyword (`mut`) for both variables and parameters

## Code Generation

### C Output for Heap Allocation

```c
// Input Czar code:
let p: *Point = new Point { x: 10, y: 20 }

// Generated C code:
Point* p = ({ 
    Point* _tmp_1 = (Point*)malloc(sizeof(Point)); 
    *_tmp_1 = (Point){ .x = 10, .y = 20 }; 
    _tmp_1; 
});
```

### C Output for Cleanup

```c
// At scope exit or before return:
free(p);
return result;
```

### C Output for let/mut Variables

```c
// Immutable (let)
const int32_t x = 10;

// Mutable (mut)
int32_t y = 20;

// Note: Pointers are never const even if immutable
Point* p = ...;  // not const Point* p
```

## Compiler Requirements

- **GNU C Extensions**: The generated C code requires GCC or Clang
- **Statement Expressions**: Uses `({ ... })` syntax for initialization
- **C99 or later**: Uses compound literals `(Type){...}`

## Testing

All existing tests have been updated to use the new syntax:

- ✅ types.cz - Basic types
- ✅ bindings.cz - Variable bindings with let/mut
- ✅ structs.cz - Struct definitions
- ✅ pointers.cz - Pointer operations
- ✅ functions.cz - Function calls
- ✅ arithmetic.cz - Arithmetic operators
- ✅ comparison.cz - Comparison operators
- ✅ if_else.cz - Conditional statements
- ✅ while.cz - While loops
- ✅ comments.cz - Comment support
- ✅ no_semicolons.cz - Optional semicolons

New tests added:

- ✅ heap_allocation.cz - Basic heap allocation with new keyword
- ✅ nested_heap.cz - Nested scope cleanup
- ✅ mut_params.cz - Mutable function parameters
- ✅ void_heap.cz - Heap allocation in void functions

**All 15 tests pass successfully.**

## Future Work

### Potential Improvements

1. **NULL Check**: Add runtime NULL checking after malloc
2. **Portable Initialization**: Alternative to GNU statement expressions
3. **Multiple Returns**: Better handling of cleanup with multiple return paths
4. **Error Handling**: Return error codes on allocation failure

### Example Future Syntax

```czar
// With error handling
p: ?*Point = try new Point { x: 10, y: 20 }
if p == null {
    return error.OutOfMemory
}
```

## Migration Guide

### For Existing Code

1. Replace `val` with `let`
2. Replace `var` with `mut`
3. Use `new TypeName { fields }` for heap allocation

### Example Migration

**Before:**
```czar
val x: i32 = 10
var y: i32 = 20
val p: *Point = &stackPoint
```

**After:**
```czar
let x: i32 = 10
mut y: i32 = 20
let p: *Point = new Point { x: 1, y: 2 }  // or &stackPoint
```

## Compatibility

- **Breaking Change**: Yes, all existing code needs to be updated
- **Migration Effort**: Low (straightforward keyword replacement)
- **Backward Compatibility**: None (this is v0, breaking changes acceptable)
