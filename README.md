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

## v0 Language Features

This is the minimal coherent slice to bootstrap the compiler.

### 1. Types (v0)

- i32
- bool
- void
- struct types
- Pointer types: *T
- Nullable pointers: *T (null allowed)
- Casts exist but are explicit:

> val x: i32 = (i32) someExpr;

### 2. Bindings

```
val x: i32 = 1;   // immutable
var y: i32 = 2;   // mutable

var z: i32;       // declared, must be assigned before first read
z = 10;
```

### 3. Pointers

```
var v: Vec2 = Vec2 { x: 1, y: 2 };
var p: *Vec2 = &v;

p.x = 10;        // auto-deref on .
(*p).y = 20;     // explicit deref if desired
```

**Semantics:**

- Param type T → passed by value.
- Param type *T → passed by pointer (allowing mutation of caller data).

### 4. Structs

```
struct Vec2 {
    x: i32;
    y: i32;
}
```

**Struct literals:**

```
val v: Vec2 = Vec2 { x: 3, y: 4 };
```

### 5. Functions

```
fn add(a: i32, b: i32) -> i32 {
    return a + b;
}
```

- Single return value.
- No multiple returns in v0.
- No generics in v0.
- No interfaces in v0.

### 6. Methods (v0: sugar built later)

Internally, methods are just functions with an explicit receiver:

```
fn length(self: *Vec2) -> i32 {
    return self.x * self.x + self.y * self.y;
}
```

v0 might require calling like: `val L: i32 = length(&v);`

Later (v1), this becomes: `val L: i32 = v.length();` with auto-addressing and auto-deref.

### 7. Extension Methods (v1+)

Any function whose first parameter is self: T or self: *T becomes callable as a method:

```
fn clamp(self: *Vec2, min: i32, max: i32) -> void { ... }

v.clamp(0, 10);
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
    ok: bool;
    value: i32;
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
  fn print(x: i32) -> void
  fn print(x: *char) -> void
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

### v1 — Ergonomics & Expressiveness

Goal: make the language comfortable

- Method syntax (obj.method(args))
- Auto-deref for field access and methods
- Extension methods
- Overloading (exact-match only)
- Nullable pointers with null literal
- Simple dead-store warnings
- Basic IR for future optimizations

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

### v3 — Serious Compiler Stuff

Goal: industrialize the toolchain

- IR-level optimizations
- Register allocation if going native
- Alternative backends (LLVM IR, Zig IR)
- Link-time optimizations
- Borrow-checker-lite for pointer safety (optional mode)
- Escape analysis
- Static analysis tools

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

### Current Implementation (v0)

The v0 compiler is now feature-complete with:

**Implemented:**
- ✅ lexer.lua - Full lexer with comment support (// and /* */)
- ✅ parser.lua - Complete parser with **optional semicolons**
- ✅ codegen.lua - C code generator
- ✅ main.lua - Compiler driver
- ✅ **cz** - Standalone compiler binary

**Features:**
- Comments: Both `//` single-line and `/* */` multi-line comments are supported
- Optional semicolons: Semicolons are now optional in all contexts (statements and struct fields)
- Types: i32, bool, void, structs, pointers (*T)
- Variables: val (immutable) and var (mutable)
- Functions with parameters and return values
- Control flow: if/else and while loops
- Operators: arithmetic (+, -, *, /), comparison (<, >, ==, !=, <=, >=), logical (&&, ||)
- Struct literals and field access

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
# Compile and run the example
make

# Run the test suite (all tests in tests/*.cz)
make test

# Clean build artifacts
make clean

# Install cz to /usr/local/bin (requires sudo)
sudo make install
```

### Testing

The project includes a comprehensive test suite in the `tests/` directory covering all v0 features:

- test_types.cz - Basic types
- test_bindings.cz - val/var bindings
- test_structs.cz - Struct definitions and literals
- test_pointers.cz - Pointer operations
- test_functions.cz - Function calls
- test_arithmetic.cz - Arithmetic operators
- test_comparison.cz - Comparison operators
- test_if_else.cz - Conditional statements
- test_while.cz - While loops
- test_comments.cz - Comment support
- test_no_semicolons.cz - Optional semicolons

Run all tests with: `make test` from the root directory.

### Next Steps

Future work (v1+) includes:
- ~~ast.lua~~ (represented as tables currently)
- typechecker.lua - Type checking and semantic analysis
- Method syntax and extension methods
- Overloading
- More types and optimizations
