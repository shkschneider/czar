# C Interop Feature

The czar language now supports interoperability with C code through a simple import mechanism.

## Syntax

```czar
import C : header1.h header2.h ...
```

This imports C header files and allows you to call C functions using the `C.` prefix.

## Usage

### Basic Example

```czar
import C : stdio.h

fn main() i32 {
    C.printf("Hello from C!\n")
    return 0
}
```

### Multiple Headers

You can import multiple C headers at once:

```czar
import C : stdio.h stdlib.h string.h

fn main() i32 {
    C.printf("Testing multiple headers\n")
    C.strlen("hello")
    return 0
}
```

### Generated Code

The czar compiler translates C interop code into regular C:

**Input (czar):**
```czar
import C : stdio.h

fn main() i32 {
    C.printf("Hello!\n")
    return 0
}
```

**Output (generated C):**
```c
#include <stdio.h>
// ... other standard includes ...

int32_t main_main() {
    printf("Hello!\n");
    return 0;
}
```

## Current Limitations

1. **Return Types**: C functions are assumed to return `void` in the type system. If you need to capture return values, you'll need explicit type annotations or casts.

2. **Type Safety**: The compiler trusts that you're calling C functions correctly. It doesn't validate function signatures or argument types for C functions.

3. **Header Resolution**: Headers are included as-is (e.g., `<stdio.h>`). The C compiler must be able to find them.

## Future Enhancements

Possible improvements for the future:
- Parse C headers to understand function signatures
- Maintain a database of common C library functions with their signatures
- Support for C structs and types
- Better type inference for C function return values
