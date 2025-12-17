# Czar

> "Veni. Vidi. Vici." ~Caesar

*Just kidding.*

This is a **toy language**, used as a playground of mine to learn more about languages and compilation.
It currently is written in Lua and transpiles to C.

## Phylosophy

- Explicit - Safe(r) - Modular
- Structs with methods but without inheritence
- Mutability - Nullability - Visibility

## Features

- Static typing with explicit types
- Modularization with `module` and `import`
- Structs with members and methods (`self`)
- Mutability `mut` (immutable by default)
- Nullability `?`, casting with `as<Type>(optional fallback)`
- Visibility with `pub` (private by default)
- Pointers with `&` (address-of) and `*` (dereference) operators
- Memory management with `new` and `free`
- Error-as-value pattern (no exceptions)
- Protections: out-of-bounds, dangling pointers, use-after-free...
- Internal types: `pair<T:T>`, `array<T>`, `map<T:T>`
- Macros: `#FILE`, `#LINE`, `#DEBUG`, `#log(...)`, `#assert(...)`...
- Some overloading...
- ...

> Someone had good intentions at each step along the way, but nobody stopped to ask why

## Binary

The compiler is built via `./build.sh`.
It produces a `./dist/cz` binary.

```
./dist/cz compile ...
./dist/cz build ...
./dist/cz run ...
./dist/cz test ...
./dist/cz inspect ...
./dist/cz format ...
./dist/cz todo|fixme ...
```

## Steps

- lexer -> tokens
- parser -> ast
- typechecker
- lowering
- analysis
- codegen -> c
+ macros builtins warnings errors
