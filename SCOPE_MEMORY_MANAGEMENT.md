# Scope-Based Memory Management in Czar

## Overview

Czar implements automatic memory cleanup for heap-allocated variables using a compile-time, scope-based approach similar to defer in Go or Zig. When you allocate memory with the `new` keyword, the compiler automatically inserts `free()` calls at scope exit.

## How It Works

### Scope Tracking

The compiler maintains a stack of scopes during code generation. Each scope tracks:
1. **Variables** - All variables declared in that scope with their types
2. **Heap Variables** - Variables that were allocated with `new`

When a scope exits (either via `return` or by reaching the end of a block), the compiler generates `free()` calls for all heap variables in that scope, in reverse order (LIFO - last allocated, first freed).

### Example

```czar
fn process_data() -> i32 {
    let a: *Point = new Point { x: 1, y: 2 }    // Tracked in function scope
    let b: *Point = new Point { x: 3, y: 4 }    // Tracked in function scope
    
    if condition {
        let c: *Point = new Point { x: 5, y: 6 }  // Tracked in if-block scope
        // ... use c ...
        // free(c) inserted here automatically
    }
    
    let result: i32 = a.x + b.y
    // free(b) inserted here
    // free(a) inserted here
    return result
}
```

### Generated C Code

```c
int32_t process_data() {
    Point* a = malloc(sizeof(Point)); // simplified
    *a = (Point){ .x = 1, .y = 2 };
    
    Point* b = malloc(sizeof(Point));
    *b = (Point){ .x = 3, .y = 4 };
    
    if (condition) {
        Point* c = malloc(sizeof(Point));
        *c = (Point){ .x = 5, .y = 6 };
        // ... use c ...
        free(c);  // automatically inserted
    }
    
    const int32_t result = a->x + b->y;
    free(b);  // automatically inserted
    free(a);  // automatically inserted
    return result;
}
```

## Limitations

### 1. Re-Assignment Memory Leaks

The compiler only tracks the initial assignment. Re-assigning a heap variable causes a leak:

```czar
fn leak_example() -> void {
    mut p: *Point = new Point { x: 1, y: 2 }  // Allocated #1
    p = new Point { x: 3, y: 4 }              // Allocated #2 - #1 LEAKS!
    // Only #2 will be freed at scope exit
}
```

**Why:** The compiler doesn't track reassignments, so it doesn't know to free the first allocation.

**Workaround:** Manual management or use immutable bindings (`let` instead of `mut`).

### 2. Arrays Not Supported

Arrays of heap-allocated objects are not handled:

```czar
// NOT SUPPORTED - will not compile or cause issues
fn array_example() -> void {
    let arr: [*Point; 3] = [
        new Point { x: 1, y: 2 },
        new Point { x: 3, y: 4 },
        new Point { x: 5, y: 6 }
    ]
    // Only the array itself might be freed, not the elements
}
```

**Why:** The language doesn't have array literals yet, and even if it did, the compiler would need to track each element separately.

**Workaround:** Manually allocate and free array elements, or use structs containing multiple values.

### 3. Linked Lists and Recursive Structures

The automatic cleanup doesn't traverse structures:

```czar
struct Node {
    value: i32
    next: *Node
}

fn list_example() -> void {
    let head: *Node = new Node { value: 1, next: null }
    let second: *Node = new Node { value: 2, next: null }
    head.next = second  // Creates a link
    
    // At scope exit, both head and second are freed
    // This works for this simple case, but...
}

fn leak_list() -> *Node {
    let head: *Node = new Node { value: 1, next: null }
    let second: *Node = new Node { value: 2, next: null }
    head.next = second
    
    return head  // Escapes scope!
    // head and second are still freed here - USE AFTER FREE BUG!
}
```

**Why:** The compiler doesn't understand ownership or references. It just frees variables at scope exit.

**Workaround:** 
- Don't return heap-allocated pointers from functions
- Implement manual `free_list()` functions for recursive structures
- Use manual memory management for complex data structures

### 4. String Memory Management

Strings (char arrays) need manual management:

```czar
// Hypothetical - strings not fully implemented yet
fn string_example() -> void {
    let s: *char = allocate_string("hello")  // Manual allocation
    // ... use s ...
    free_string(s)  // Must free manually
}
```

**Why:** Strings are typically allocated with different mechanisms (strlen + malloc), and the compiler can't distinguish them from regular pointers.

### 5. Aliasing Issues

The compiler doesn't track aliases:

```czar
fn alias_problem() -> void {
    let p: *Point = new Point { x: 1, y: 2 }
    let q: *Point = p  // q is an alias for p
    
    // Both p and q point to the same memory
    // But only p is tracked for cleanup
    // Using q after this function is a use-after-free
}
```

**Why:** The compiler only tracks the variable that was directly assigned with `new`.

**Workaround:** Don't create aliases to heap-allocated pointers, or ensure they don't escape scope.

### 6. Returning Heap Pointers

Returning a heap-allocated pointer from a function causes use-after-free:

```czar
fn create_point() -> *Point {
    let p: *Point = new Point { x: 10, y: 20 }
    return p
    // free(p) is called here before the return!
}

fn main() -> i32 {
    let point: *Point = create_point()
    return point.x  // Use-after-free!
}
```

**Why:** The cleanup happens at function scope exit, which includes before returns.

**Workaround:** 
- Pass pointers to fill (out parameters)
- Use stack allocation instead
- Implement manual memory management for APIs that need to return allocated memory

### 7. Conditional Cleanup Complexity

Complex control flow can be tricky:

```czar
fn complex_flow(condition: bool) -> i32 {
    let p: *Point = new Point { x: 1, y: 2 }
    
    if condition {
        return p.x  // free(p) inserted before return
    }
    
    // If we didn't return, p is freed here too
    return 0
}
```

**Why:** The compiler inserts cleanup before every return statement in the scope.

**Note:** This actually works correctly but uses more code than necessary.

## Best Practices

1. **Keep It Simple**: Use `new` for simple, single-object allocations that live within one function.

2. **Avoid Mutation**: Use `let` (immutable) instead of `mut` for heap-allocated pointers to avoid reassignment leaks.

3. **Stack When Possible**: Prefer stack allocation for small, short-lived objects.

4. **Manual for Complex**: Use manual malloc/free for:
   - Data structures (linked lists, trees, graphs)
   - Strings
   - Arrays of pointers
   - Objects that need to escape scope

5. **Document Ownership**: Clearly document which functions own memory and which don't.

## Future Improvements

Potential enhancements that could address these limitations:

1. **Ownership Tracking**: Track which function owns a pointer (like Rust)
2. **Move Semantics**: Allow transferring ownership when returning
3. **Reference Counting**: Automatic reference counting for shared ownership
4. **Destructor Functions**: Allow types to define cleanup logic
5. **Linear Types**: Ensure heap allocations can't be copied, only moved
6. **Smart Pointers**: Wrapper types that handle cleanup automatically

For now, the current implementation provides a nice convenience for simple cases while remaining explicit about its limitations.
