# Czar

> A small, explicit, low-level, statically typed systems language.

Czar is a personal “better C” project, inspired by C, Zig, Jai, Go, and Kotlin extension ergonomics, but with its own philosophy:

- Explicit over magical
- Static types
- Value semantics by default
- Pointers when needed
- Method extensions
- Error-as-value
- C-level performance
- No GC
- Simple, friendly compiler errors

The compiler is written in Lua, and transpiles to portable C as the primary backend.

## Goals

### Primary Goals

- Learn how compilers work: parsing, semantic analysis, type-checking, lowering, optimization.
- Produce a small, predictable systems language with:
    - value semantics,
    - pointers,
    - static typing,
    - clear errors,
    - minimal implicit behavior.

### Secondary Goals

- Enable ergonomic method calls and extension methods.
- Allow overloading (strict, no implicit conversions).
- Introduce generics and interfaces later, once the core is solid.
- Build optimization passes (constant folding, basic dead-store elimination, inlining).

### Non-Goals

- No exceptions.
- No inheritance.
- No implicit conversions between unrelated types.
- No hidden memory behaviors.
- No GC or reference counting runtime in the language core.
- No trying to replace C++ or Rust.

## Language Philosophy

Czar is “C with sane defaults”:

- Memory is explicit.
- Mutability is explicit.
- Control flow is simple.
- Nothing implicit unless explicitly listed.
- Zero magic conversions.

Compiler produces straightforward portable C.

## Syntax

Czar uses a **type-first syntax** where types come before names:

```czar
val i32 x = 42                // immutable variable
var Vec2 v = Vec2 { x: 1, y: 2 }  // mutable variable
fn add(i32 a, i32 b) -> i32   // function parameters
struct Point {
    i32 x                      // struct fields
    i32 y
}
```

**Pointers** are denoted with `*` after the type name:

```czar
var Vec2* p = &v              // pointer to Vec2
fn modify(Vec2* p) -> void    // function taking pointer
```

The `*` indicates both that it's a pointer and that the data can be modified through it.

## v0 Language Features

This is the minimal coherent slice to bootstrap the compiler.

### 1. Types (v0)

- i32
- bool
- void
- struct types
- Pointer types: T*
- Nullable pointers: T* (null allowed)
- Casts exist but are explicit:

> val i32 x = (i32) someExpr

### 2. Bindings

```
val i32 x = 1   // immutable
var i32 y = 2   // mutable

var i32 z       // declared, must be assigned before first read
z = 10
```

### 3. Pointers

```
var Vec2 v = Vec2 { x: 1, y: 2 }
var Vec2* p = &v

p.x = 10        // auto-deref on .
(*p).y = 20     // explicit deref if desired
```

**Semantics:**

- Param type T → passed by value.
- Param type T* → passed by pointer (allowing mutation of caller data).

### 4. Structs

```
struct Vec2 {
    i32 x
    i32 y
}
```

**Struct literals:**

```
val Vec2 v = Vec2 { x: 3, y: 4 }
```

### 5. Functions

```
fn add(i32 a, i32 b) -> i32 {
    return a + b
}
```

- Single return value.
- No multiple returns in v0.
- No generics in v0.
- No interfaces in v0.

### 6. Methods (v0: sugar built later)

Internally, methods are just functions with an explicit receiver:

```
fn length(Vec2* self) -> i32 {
    return self.x * self.x + self.y * self.y
}
```

v0 might require calling like: `val i32 L = length(&v)`

Later (v1), this becomes: `val i32 L = v.length()` with auto-addressing and auto-deref.

### 7. Extension Methods (v1+)

Any function whose first parameter is T* self or T self becomes callable as a method:

```
fn clamp(Vec2* self, i32 min, i32 max) -> void { ... }

v.clamp(0, 10)
```

Works across modules. No inheritance required.

### 8. Overloading (v1)

Overloading resolution is exact-match only:

- Same name allowed if parameter types differ.
- No implicit conversions.
- Return type alone cannot differentiate overloads.
- Ambiguous calls are a compiler error.

### 9. Error-as-Value (v0)

No generics yet. Users define result wrappers manually:

```
struct ParseIntResult {
    bool ok
    i32 value
}
```

Later (v2+), this may become: `Result<T, E>` with monomorphization.

### 10. Control Flow

```
if x > 0 {
    ...
} else {
    ...
}

while x < 10 {
    ...
}
```

Parentheses optional depending on taste; grammar supports both.

### 11. Evaluation Order

- Strict left-to-right for all expression evaluation.
- `&&` and `||` are short-circuiting.
- Compiler may introduce temporaries in generated C to preserve these guarantees.

## Compiler Architecture

Written in Lua, producing portable C.

**Pipeline:**

```
source.my
   ↓
lexer.lua        → tokens
   ↓
parser.lua       → AST
   ↓
typechecker.lua  → typed AST (with mutability rules, overload checks later)
   ↓
c_codegen.lua    → .c output
   ↓
clang/gcc/msvc   → native binary
```

**Later Pipelines**

You can add:

- IR lowering
- optimization passes (constant folding, dead-store elimination)
- alternative backends (Zig, LLVM IR) for experiments

But C stays the reference backend.

## Diagnostics Philosophy

Czar's compiler prioritizes clear, specific error messages.

**Examples:**

Mutability mismatch

```
error: cannot pass immutable value to function requiring a mutable pointer
  --> main.my:12:9
   |
12 |     v.translate(1, 2);
   |     ^ immutable binding
note: `translate` requires parameter of type `*Vec2`
  --> vec2.my:1:1
```

Overload resolution (v1)

```
error: no overload of `print` matches argument types (`bool`)
  --> main.my:7:5
note: candidates:
  fn print(i32 x) -> void
  fn print(char* x) -> void
```

Type mismatch

```
error: mismatched types: expected i32, found bool
  --> main.my:5:22
```

## Roadmap

### v0 — Walking Compiler (Foundations)

Goal: compile trivial programs to C and run them

- Lexer
- Parser (structs, functions, vars, blocks, if/while)
- AST shape finalized
- Types: i32, bool, void, structs, pointers
- Bindings: val / var

C code generation for:

- struct definitions
- simple functions
- variable declarations
- arithmetic
- conditionals, loops

Good diagnostics for:

- type mismatch
- mutability mismatch
- undeclared identifier
- missing return
- No methods yet (call them as plain functions)
- No overloading
- No generics
- No interfaces

Output: You can write a small C-like program in Czar and get a native binary.

**Bonus:**

- tests
- standard library
  - log
  - print
  - debug/assert/macros...

### v1 — Ergonomics & Expressiveness

Goal: make the language comfortable

- Method syntax (obj.method(args))
- Auto-deref for field access and methods
- Extension methods
- Overloading (exact-match only)
- Nullable pointers with null literal
- Simple dead-store warnings
- Basic IR for future optimizations

**Bonus:**

- i/o: open/read/write/close file
- net: tcp/udp/http

### v2 — Power Features

Goal: add the fun stuff without breaking the philosophy

- Generics (monomorphized):
    - Option<T>
    - Result<T, E>
- Basic interfaces (nominal)
- Module visibility / exports
- Inline functions
- Basic compile-time evaluation (constants)
- More numeric types (u32, i64, f64, etc.)

**Bonus:**

- coroutines

### v3 — Serious Compiler Stuff

Goal: industrialize the toolchain

- IR-level optimizations
- Register allocation if going native
- Alternative backends (LLVM IR, Zig IR)
- Link-time optimizations
- Borrow-checker-lite for pointer safety (optional mode)
- Escape analysis
- Static analysis tools

**Bonus:**

- memory management
- packager/libraries

## Why C as the Backend?

- Portable and stable ABI
- Extremely predictable semantics
- Best route for a “better C”
- Easy interop with existing systems
- Gives your compiler maximum responsibility (you learn more)
- Enables very small runtime
- Lets clang/GCC do heavy optimizations
- Later you can add secondary backends (Zig, LLVM IR) as experiments.

## Status

### Current Implementation (v0 → v1 in progress)

The compiler has completed v0 and is now halfway to v1 with core ergonomic features:

**Implemented:**
- ✅ lexer.lua - Full lexer with comment support (// and /* */)
- ✅ parser.lua - Complete parser with **optional semicolons** and **method syntax**
- ✅ codegen.lua - C code generator with **method call resolution**
- ✅ main.lua - Compiler driver
- ✅ **cz** - Standalone compiler binary

**v0 Features (Complete):**
- Comments: Both `//` single-line and `/* */` multi-line comments are supported
- Optional semicolons: Semicolons are now optional in all contexts (statements and struct fields)
- Types: i32, bool, void, structs, pointers (T*)
- Variables: val (immutable) and var (mutable)
- Functions with parameters and return values
- Control flow: if/else and while loops
- Operators: arithmetic (+, -, *, /), comparison (<, >, ==, !=, <=, >=), logical (&&, ||)
- Null-safety operators: `!!` (null-check), `??` (null-coalescing), `?.` (safe navigation)
- Struct literals and field access

**v1 Features (Halfway Complete):**
- ✅ **Expanded types**: i64, u32, u64, f32, f64 in addition to i32
- ✅ **Method syntax**: Define methods as `fn Type.method(Type* self) -> ReturnType`
- ✅ **Extension methods**: Any function with first parameter named `self` is callable as a method
- ✅ **Auto-addressing**: Methods automatically convert values to pointers when needed
- ✅ **Error-as-value**: Pattern demonstrated with Result-style structs
- ⏳ **Overloading**: Not yet implemented (planned)
- ⏳ **Nullable pointers with explicit null checks**: Partially supported

### Usage

**Using the `cz` compiler binary:**

```bash
# Compile a .cz file to a.out
./cz program.cz

# Compile with custom output name
./cz program.cz -o my_program

# Run the compiled binary
./a.out
```

**Using make:**

```bash
# Build the compiler (dynamic linking, optimized and stripped)
make build

# Build with static linking (portable, no runtime dependencies)
make STATIC=1 build

# Run the test suite (all tests in tests/*.cz)
make test

# Build and run tests
make all

# Clean build artifacts
make clean

# Install cz to /usr/local/bin (requires sudo)
sudo make install

# Show help with all options
make help
```

**Build Features:**
- Optimized with `-O2` for better performance
- Stripped with `-s` for minimal binary size (~31KB dynamically linked)
- Optional static linking with `STATIC=1` (~1.7MB, fully portable)
- Dynamic linking by default (smaller binary, requires libluajit-5.1.so)

### Testing

The project includes a comprehensive test suite in the `tests/` directory covering v0 and v1 features:

**v0 Tests:**
- types.cz - Basic types (i32, bool, void)
- bindings.cz - val/var bindings
- structs.cz - Struct definitions and literals
- pointers.cz - Pointer operations
- functions.cz - Function calls
- arithmetic.cz - Arithmetic operators
- comparison.cz - Comparison operators
- if_else.cz - Conditional statements
- while.cz - While loops
- comments.cz - Comment support
- no_semicolons.cz - Optional semicolons
- logical_operators.cz - Logical operators (&&, ||)
- null_pointer.cz - Null pointer literal
- field_assignment.cz - Struct field assignment

**v1 Tests:**
- new_types.cz - New numeric types (i64, u32, u64, f32, f64)
- methods.cz - Method syntax (Type.method)
- extension_methods.cz - Extension methods with self parameter
- error_as_value.cz - Error-as-value pattern
- comprehensive.cz - Integration test combining all v1 features

Run all tests with: `make test` from the root directory.

### Example

```czar
// Example demonstrating v1 features
struct Vec2 {
    i32 x
    i32 y
}

// Method syntax: Type.method(self, ...)
fn Vec2.length(Vec2* self) -> i32 {
    return self.x * self.x + self.y * self.y
}

// Extension method
fn scale(Vec2* self, i32 factor) -> void {
    self.x = self.x * factor
    self.y = self.y * factor
}

fn main() -> i32 {
    var Vec2 v = Vec2 { x: 3, y: 4 }

    // Call methods with auto-addressing
    val i32 l = v.length()  // No need for &v
    v.scale(2)

    return l  // returns 25
}
```

### Next Steps

Future work (v1 completion and v2) includes:
- ~~ast.lua~~ (represented as tables currently)
- typechecker.lua - Type checking and semantic analysis
- ~~Method syntax and extension methods~~ ✅ (Complete)
- Overloading (exact-match only)
- ~~More numeric types~~ ✅ (Complete)
- Nullable pointers with null literal (partially done)
- IR lowering and optimization passes
