# Module System Documentation

This document describes the module system features added to Czar.

## Features

### 1. Module Declaration

Declare a module at the top of your file:

```czar
module mylib

pub fn add(i32 a, i32 b) i32 {
    return a + b
}
```

The `module` declaration must come first, before any imports or other declarations.

### 2. Import Statements

Import other modules:

```czar
import cz.io
import cz.math
```

Import with an alias:

```czar
import cz.io as io
```

The default alias for `import cz.io` is `io` (the last component of the path).

### 3. Visibility Modifiers

By default, all declarations (functions, structs, enums) are private to the module.
Use the `pub` keyword to make them public:

```czar
pub struct Point {
    i32 x
    i32 y
}

pub fn create_point(i32 x, i32 y) Point {
    Point p = Point { x: x, y: y }
    return p
}

// This function is private (module-local)
fn internal_helper() i32 {
    return 42
}
```

### 4. Unused Import Warnings

The compiler warns about unused imports:

```czar
import cz.math  // WARNING: Unused import 'cz.math'

fn main() i32 {
    return 0
}
```

If you use a custom alias, it's shown in the warning:

```czar
import cz.io as myio  // WARNING: Unused import 'cz.io' (aliased as 'myio')

fn main() i32 {
    return 0
}
```

## Current Limitations

This is a foundational implementation. Currently:

- Modules and imports are parsed and tracked but don't affect name resolution yet
- The `pub` modifier is stored but visibility is not enforced across files
- Single-file compilation is supported; multi-file compilation is planned for the future
- No namespace prefixes are generated in the C output yet

The syntax is in place and working, making it easy to extend the compiler to support full cross-file module imports in the future.

## Examples

See the test files for working examples:
- `tests/ok/module_basic.cz` - Basic module declaration
- `tests/ok/pub_function.cz` - Public and private functions
- `tests/ok/pub_struct.cz` - Public and private structs
- `tests/ok/import_unused.cz` - Unused import warning
- `tests/ok/import_with_alias.cz` - Import with default alias
- `tests/ok/import_custom_alias.cz` - Import with custom alias
