# Czar

> Caesar: "Veni. Vidi. Vici."

*Just kidding.*

This is a toy language I'm trying to make to learn more about languages and compilation.

- Static typing with explicit type annotations
- Value semantics by default
- Explicit mutability via  mut  keyword
- Pointers with  &  (address-of) and  *  (dereference) operators
- Structs with fields and methods
- Method syntax with  :  operator (e.g.,  obj:method() )
- Extension methods that can be defined outside the struct
- Memory management with explicit  new  and  free
- Error-as-value pattern (no exceptions)
- Null safety features with  ?  and  !!  operators
- Type casting with  cast<Type>  syntax
- Arrays with compile-time bounds checking
- Dynamic arrays (lists) with  new [...]  syntax for heap allocation
- Internal types: pair<T:U>, array<T>, map<K:V> as struct-like types
- Stack and heap allocation for internal types (heap with  new  keyword)
- Directives for compile-time configuration (#FILE, #FUNCTION, #DEBUG, etc.)

> Someone had good intentions at each step along the way, but nobody stopped to ask why

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
