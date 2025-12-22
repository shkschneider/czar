# Memory Handling with #defer and #alloc

This document describes the new memory handling features in Czar: the `#defer` directive and the `#alloc` directive.

## The `#defer` Directive

The `#defer` directive allows you to defer the execution of a statement until the current scope exits. Deferred statements execute in LIFO (Last-In-First-Out) order.

### Basic Usage

```czar
fn main() i32 {
    any p = new ...
    #defer free(p)

    // Use p here

    // No explicit free needed - defer will handle it at scope exit
    return 0
}
```

### Multiple Defer Statements

When you have multiple defer statements, they execute in reverse order:

```czar
fn main() i32 {
    any p1 = new ...
    #defer free(p1)    // Executes last

    any p2 = new ...
    #defer free(p2)    // Executes second

    any p3 = new ...
    #defer free(p3)    // Executes first

    return 0
}
// Execution order at scope exit: free(p3), free(p2), free(p1)
```

### Defer with Nested Scopes

Deferred statements are scoped to the block they are declared in:

```czar
fn main() i32 {
    {
        any p1 = new ...
        #defer free(p1)
        // p1 freed here at inner scope exit
    }

    {
        any p2 = new ...
        #defer free(p2)
        // p2 freed here at inner scope exit
    }

    return 0
}
```

### Defer vs Automatic Free

Czar supports two mechanisms for memory cleanup:

1. **Automatic free-at-scope-exit**: Variables allocated with `new` are automatically freed when they go out of scope (unless explicitly freed)
2. **#defer**: Explicitly defer execution of any statement (including `free`) to scope exit

The `#defer` directive gives you more control and can be used for any cleanup operation, not just freeing memory (e.g., closing files, releasing resources).

## The `#alloc` Directive

The `#alloc` directive allows you to specify a custom allocator interface for memory allocation.

### Basic Usage

```czar
#alloc cz.alloc  // Use the default Czar allocator

fn main() i32 {
    any p = new ...
    #defer free(p)
    return 0
}
```

### Allocator Interface

The allocator must implement the following interface:

```czar
iface Alloc {
    fn malloc(u32 size) any
    fn realloc(any ptr, u32 size) any  // size is new size
    fn free(any ptr) void
}
```

### Custom Allocator Example

```czar
#alloc my.custom.allocator

// Your custom allocator implementation must provide:
// - malloc(u32 size) -> any
// - realloc(any ptr, u32 size) -> any
// - free(any ptr) -> void

fn main() i32 {
    any p = new ...  // Uses my.custom.allocator.malloc
    #defer free(p)   // Uses my.custom.allocator.free
    return 0
}
```

## Best Practices

1. **Use `#defer` for explicit cleanup**: When you need precise control over when cleanup happens
2. **Use automatic free for simple cases**: Let the compiler handle freeing for you
3. **Use `#alloc` for custom allocators**: When you need a complete allocator interface
4. **Combine `#defer` with other cleanup operations**: Not just memory, but files, locks, etc.

Example combining multiple features:

```czar
#alloc cz.alloc

fn process_file() i32 {
    any file = open("data.txt")
    #defer close(file)

    any buffer = new Buffer { size: 1024 }
    #defer free(buffer)

    // Process file with buffer
    // Both cleanup operations happen automatically at scope exit

    return 0
}
```
