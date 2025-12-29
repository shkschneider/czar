# Coroutines API Documentation

The `cz.co` module provides coroutine support using POSIX `makecontext`/`swapcontext`/`getcontext`/`setcontext` functions for cooperative multitasking.

## Types

### `Coroutine`
A coroutine handle that manages execution context and state.

```cz
Coroutine? co = new Coroutine {}
```

### `CoState`
Enum representing the coroutine's current state:
- `READY` - Created but not started
- `RUNNING` - Currently executing
- `SUSPENDED` - Yielded, waiting to be resumed
- `DEAD` - Finished execution

## Methods

### `Coroutine:resume() i32`
Resumes or starts the coroutine execution and returns the yielded value.

```cz
i32 value = co:resume()
```

### `Coroutine:is_dead() bool`
Returns `true` if the coroutine has finished execution.

```cz
if co:is_dead() {
    printf("Coroutine finished\n")
}
```

### `Coroutine:is_ready() bool`
Returns `true` if the coroutine is ready to start (not yet executed).

### `Coroutine:is_running() bool`
Returns `true` if the coroutine is currently running.

### `Coroutine:is_suspended() bool`
Returns `true` if the coroutine has yielded and is waiting to be resumed.

### `Coroutine:state() CoState`
Returns the current state of the coroutine.

```cz
CoState state = co:state()
```

### `Coroutine:wait() void`
Runs the coroutine until it completes (i.e., until `is_dead()` returns true).

```cz
co:wait()  // Blocks until coroutine finishes
```

## Functions

### `yield(i32 value) void`
Yields control from the coroutine back to the caller, passing a value.

**Note:** This function should only be called from within a coroutine context.

```cz
yield(42)  // Yield value 42 and suspend
```

## Usage Example

Due to current language limitations with function pointers, coroutines need to be initialized using `#unsafe` blocks with inline C code:

```cz
#import cz.co.*
#import cz.fmt.*

fn main() i32 {
    // Create a coroutine
    Coroutine? co = new Coroutine {}
    
    #unsafe {
        // Define the coroutine function in C
        void counter() {
            for (uint8_t c = 1; c <= 10; c++) {
                _cz_co_yield((int32_t)c);
            }
        }
        
        // Initialize the coroutine with this function
        co->handle = _cz_co_init(counter);
    }
    
    printf("coroutine launched\n")
    
    // Resume the coroutine multiple times
    while not co:is_dead() {
        i32 val = co:resume()
        if not co:is_dead() {
            printf("Yielded: %d\n", val)
        }
    }
    
    // Clean up
    free co
    
    return 0
}
```

## Advanced Example: Multiple Coroutines

You can have multiple coroutines running concurrently in a cooperative manner:

```cz
#import cz.co.*
#import cz.fmt.*

fn main() i32 {
    Coroutine? co1 = new Coroutine {}
    Coroutine? co2 = new Coroutine {}
    
    #unsafe {
        void task1() {
            for (uint8_t i = 0; i < 5; i++) {
                _cz_co_yield(i * 10);
            }
        }
        
        void task2() {
            for (uint8_t i = 0; i < 5; i++) {
                _cz_co_yield(i * 100);
            }
        }
        
        co1->handle = _cz_co_init(task1);
        co2->handle = _cz_co_init(task2);
    }
    
    // Alternate between coroutines
    while not co1:is_dead() and not co2:is_dead() {
        i32 val1 = co1:resume()
        i32 val2 = co2:resume()
        printf("co1: %d, co2: %d\n", val1, val2)
    }
    
    free co1
    free co2
    
    return 0
}
```

## Implementation Details

- Coroutines use a stack size of 8KB (CZ_CO_STACK_SIZE)
- Context switching is implemented using POSIX ucontext API
- The coroutine is automatically cleaned up when freed or when its destructor is called
- Yielded values are passed as `i32` (32-bit integers)

## Limitations

- Function pointers are not yet fully supported in Czar, so coroutine functions must be defined inline in `#unsafe` blocks
- Coroutines use POSIX ucontext which may not be available on all platforms (works on Linux and macOS)
- The maximum stack size is fixed at compile time
- Only `i32` values can be yielded between coroutine and caller
