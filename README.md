# Czar

<<<<<<< HEAD
> Caesar: "Veni. Vidi. Vici."
=======
> A small, often explicit, low-level, statically typed systems language.
>>>>>>> c5ce96c (readme)

*Just kidding.*

<<<<<<< HEAD
This is a toy language I'm trying to make to learn more about languages and compilation.
=======
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
>>>>>>> c5ce96c (readme)

> Someone had good intentions at each step along the way, but nobody stopped to ask why

- [extended-c](https://github.com/shkschneider/czar/tree/extended-c)
    is a branch with .h/.c files to extend on the standard c library in an effort to make C better for me
- [lua-to-c](https://github.com/shkschneider/czar/tree/lua-to-c)
    is a transpiler from .cz to .c first written in lua then self-hosted

## Primary Goals

- Learn how compilers work: parsing, semantic analysis, type-checking, lowering, optimization.
- Produce a small, predictable systems language with:
    - value semantics,
    - pointers,
    - static typing,
    - clear errors,
    - minimal implicit behavior.

## Secondary Goals

- Enable ergonomic method calls and extension methods.
- Allow overloading (strict, no implicit conversions).
- Introduce generics and interfaces later, once the core is solid.
- Build optimization passes (constant folding, basic dead-store elimination, inlining).

## Non-Goals

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
