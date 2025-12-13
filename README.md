# Czar

> A small, often explicit, low-level, statically typed systems language.

Czar is a personal “better C” project, inspired by C, Zig, Jai, Go, and Kotlin extension ergonomics, but with its own philosophy:

- Explicit over magical
- Static types
- Value semantics by default
- Explicit `mut`ability
- Implicit pointers (no `&` nor `*`)
- Stack/Heap allocations + defer free (no GC)
- Structs with methods and static functions + extensions
- Error-as-value
- C-level performance
- Goal: Simple, friendly compiler errors

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

Czar is "C with sane defaults" with some of my own "twists":

- Memory is explicit.
- Mutability is explicit.
- Control flow is simple.
- Nothing implicit unless explicitly listed.
- Zero magic conversions.

Compiler produces straightforward portable C.

## Syntax

Czar uses a **type-first syntax** where types come before names:

```czar
i32 x = 42                        // immutable variable
mut Vec2 v = Vec2 { x: 1, y: 2 }  // mutable variable
fn add(i32 a, i32 b) -> i32       // function parameters
struct Point {
    i32 x                         // struct fields
    i32 y
}
```

**Pointers** are automatic; no `*`:

```czar
Vec2 p = Vec2 {}              // pointer to Vec2
fn modify(mut Vec2 p) -> void // function modifying p
```

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

> i32 x = cast<i32> someExpr

### 2. Bindings

```
i32 x = 1       // immutable
mut i32 y = 2   // mutable

i32 z           // declared, must be assigned before first read
z = 10
```

### 3. Pointers

```
mut Vec2 v = Vec2 { x: 1, y: 2 }
mut Vec2 p = v  // implicit pointer

p.x = 10        // auto-deref on .
```

**Semantics:**

- Param type `T` → passed by value.
- Param type `mut T` → passed by pointer.

### 4. Structs

```
struct Vec2 {
    i32 x
    i32 y
}
```

**Struct literals:**

```
Vec2 v = Vec2 { x: 3, y: 4 }
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
fn Vec2:length() -> i32 { // implicit (mutable) self
    return self.x * self.x + self.y * self.y
}
```

v0 might require calling like: `i32 L = Vec2.length(v)`

Later (v1), this becomes: `i32 L = v:length()` with auto-addressing and auto-deref.

### 7. Extension Methods (v1+)

Any function whose first parameter is T* self or T self becomes callable as a method:

```
fn Vec2:clamp(i32 min, i32 max) -> void { ... }

v:clamp(0, 10)
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
} elseif x == 0 {
    ...
} else {
    ...
}

while x < 10 {
    ...
}
```

Parentheses optional depending on taste; grammar supports both.

**Note:** Both `elseif` (single keyword) and `else if` (two keywords) are supported for backward compatibility.

### 11. Evaluation Order

- Strict left-to-right for all expression evaluation.
- `and` and `or` are short-circuiting logical operators.
- `or` also serves as the null-coalescing operator.
- Compiler may introduce temporaries in generated C to preserve these guarantees.

### 12. Null Safety

- `!` (postfix): Null-check operator - crashes if value is null
- `or`: Null-coalescing operator - returns right operand if left is null/falsy
- Direct field access with `.` - no special safe navigation operator
- Nullable types can be represented as `Type` (pointer semantics)

### 13. Numeric Literals

- Underscore `_` can be used as a separator in numeric literals for readability
- Example: `1_000_000` is equivalent to `1000000`
- Underscores are ignored during lexing

### 14. Compiler Directives

Directives provide compile-time information and control, starting with `#`:

- **`#FILE`**: Returns the source filename as a string
- **`#FUNCTION`**: Returns the current function name as a string
- **`#DEBUG`**: Returns `false` normally, `true` with `--debug` flag

Example:
```czar
fn process(i32 x) -> i32 {
    bool debug = #DEBUG
    
    if debug {
        // Debug-only code - zero overhead in release builds
        return x * 2
    }
    
    return x
}
```

See [COMPILER_DIRECTIVES.md](COMPILER_DIRECTIVES.md) for complete documentation.

## Compiler Architecture

Written in Lua, producing portable C.

**Pipeline:**

```
source.cz
   ↓
lexer.lua        → tokens
   ↓
parser.lua       → AST
   ↓
typechecker.lua  → typed AST
   ↓
codegen.lua      → source.c output
   ↓
clang/gcc/msvc   → native binary
```

**Later Pipelines**

You can add:

- IR lowering
- optimization passes (constant folding, dead-store elimination)
- alternative backends (Zig, LLVM IR) for experiments

But C stays the reference backend.

## Roadmap

### v0 — Working Compiler (Foundations)

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
- Operators: arithmetic (+, -, *, /), comparison (<, >, ==, !=, <=, >=), logical (`and`, `or`)
- Null-safety operators: `!` (null-check), `or` (null-coalescing/logical OR)
- Numeric literals: Underscore `_` separator supported (e.g., `1_000`)
- Struct literals and field access

**v1 Features (Halfway Complete):**
- ✅ **Expanded types**: i64, u32, u64, f32, f64 in addition to i32
- ✅ **Method syntax**: Define methods as `fn Type.method(Type* self) -> ReturnType`
- ✅ **Extension methods**: Any function with first parameter named `self` is callable as a method
- ✅ **Auto-addressing**: Methods automatically convert values to pointers when needed
- ✅ **Error-as-value**: Pattern demonstrated with Result-style structs
- ✅ **Compiler directives**: `#FILE`, `#FUNCTION`, `#DEBUG` for compile-time information
- ⏳ **Overloading**: Not yet implemented (planned)
- ⏳ **Nullable pointers with explicit null checks**: Partially supported
- `#` talks to the compiler (see COMPILER_DIRECTIVES.md)
- `@` is for interfaces

### Usage

```
./build.sh
./cz ...
```

**Build Features:**
- Optimized with `-O2` for better performance
- Stripped with `-s` for minimal binary size
- Automatic static linking if `luastatic` is available (~1.8MB, fully portable)
- Falls back to dynamic linking if `luastatic` is not found (~79KB, requires libluajit-5.1.so.2)

**Note:** When building with static linking, the linker will produce a warning about `dlopen` usage in statically linked applications. This is expected behavior due to LuaJIT's FFI (Foreign Function Interface) and does not indicate a build failure.

### Testing

The project includes a comprehensive test suite in the `tests/` directory covering v0 and v1 features:

Run all tests with: `./check.sh` from the root directory.
