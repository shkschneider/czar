# CZar Module System

CZar supports modularization of C code through an implicit module system based on directory structure.

## How It Works

### Implicit Modules

- Each directory is a module
- Files in the same directory are part of the same module
- Files in the same module can see each other's functions/types without imports

### Explicit Imports

Use `#import "path/to/module"` to import declarations from another module:

```c
#import "lib"        // Import from lib/ directory
#import "utils/math" // Import from utils/math/ directory

int main(void) {
    // Can now use functions from lib/*
    Point p = create_point(10, 20);
    return 0;
}
```

## Building Multi-File Projects

Use the provided build script:

```bash
./scripts/czar-build.sh <directory> [output_binary_name]
```

Example:
```bash
./scripts/czar-build.sh test/multifiles myprogram
```

The build script:
1. Transpiles all `.cz` files to `.c`
2. Generates `.h` headers with function declarations
3. Adds `#include` directives for same-directory files
4. Compiles all `.c` files to object files
5. Links everything into an executable

## Example Project Structure

```
myproject/
├── main.cz           # Main entry point
├── helpers.cz        # Helper functions (same module as main)
└── lib/
    ├── types.cz      # Type definitions
    └── utils.cz      # Utility functions
```

In `main.cz`:
```c
// No import needed for helpers.cz (same directory)
#import "lib"  // Import lib module

int main(void) {
    helper_function();  // From helpers.cz
    lib_function();     // From lib/*.cz
    return 0;
}
```

## Generated Files

For each `.cz` file, the build process generates:
- `.cz.c` - Transpiled C code
- `.cz.h` - Header with function declarations
- `.cz.o` - Compiled object file

These are build artifacts and should be added to `.gitignore`.

## Current Limitations

- The `#import` directive is currently translated to a comment placeholder
- Header generation is done by the build script, not the transpiler itself
- Only function declarations are extracted to headers (not all types yet)
- Circular dependencies between modules are not checked

## Future Improvements

- Full integration of header generation into the transpiler
- Proper handling of `#import` directives
- Struct and enum declarations in headers
- Module dependency analysis
- Better error messages for missing imports
