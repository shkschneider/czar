# Compiler Directives

Czar uses compiler directives (prefixed with `#`) for compile-time features like declaring modules, importing modules and C interop.

## #module Directive

The `#module` directive is **optional** and declares which module the current file belongs to.

### Implicit Modules

By default, modules are inferred from the directory structure:
- `main.cz` → no module (top-level)
- `mod1/file1.cz` → module `mod1`
- `mod2/submod1/test1.cz` → module `mod2.submod1`

### Flattening with #module

You can use `#module` to flatten subdirectories into a parent module:

```czar
// In mod2/submod1/test1.cz
#module mod2

fn helper() i32 {
    return 42
}
```

This makes `test1.cz` part of module `mod2` instead of `mod2.submod1`, allowing you to split large modules across subdirectories.

### Rules

1. **Module names must be single words** (no dots): `#module mod2`, not `#module mod2.submod1`
2. **Can only declare ancestor directories**: A file in `mod2/submod1/` can declare `#module mod2` but not `#module mod1`
3. **`main` is special**: Can be declared anywhere as an entry point

## #import Directive

The `#import` directive imports modules or C headers.

### Regular Module Import

```czar
#import cz
#import cz.math

fn main() i32 {
    cz.print("Hello!\n")
    return 0
}
```

You can also use an alias:

```czar
#import cz.math as math

fn main() i32 {
    let pi = math.PI
    return 0
}
```

### C Interop

Import C headers to call C functions directly:

```czar
#import C : stdio.h stdlib.h

fn main() i32 {
    C.printf("Hello from C!\n")
    return 0
}
```

Headers are space-separated, not comma-separated.

## #use Directive

The `#use` directive "flattens" a module's namespace, allowing you to call its functions without the module prefix.

### Basic Usage

```czar
#import cz
#use cz

fn main() i32 {
    // Can now call print directly without cz. prefix
    print("Hello!\n")
    println("Flattened namespace!")
    return 0
}
```

### Shorthand Syntax

You can use a shorthand where `#use` immediately after `#import` automatically uses that module:

```czar
#import cz #use

fn main() i32 {
    // No need to specify module name after #use
    print("Shorthand syntax!\n")
    return 0
}
```

### Inline Syntax

You can combine directives on the same line with semicolons:

```czar
#import cz ; #use cz

fn main() i32 {
    print("Inline syntax works!\n")
    return 0
}
```

### Requirements

- A module must be imported before it can be used with `#use`
- The `#use` directive only works with modules, not C headers

### Example

```czar
#import cz
#use cz

fn main() i32 {
    // These all work without cz. prefix:
    print("Message 1\n")
    println("Message 2")
    printf("Message %d\n", 3)
    return 0
}
```

## Generated Code

The compiler treats directives at compile-time. For C interop:

**Input:**
```czar
#import C : stdio.h

fn main() i32 {
    C.printf("Hello!\n")
    return 0
}
```

**Generated C:**
```c
#include <stdio.h>

int32_t main_main() {
    printf("Hello!\n");
    return 0;
}
```

For flattened modules, the compiler automatically resolves function calls to the correct module.
