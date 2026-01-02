# CZar Roadmap

This document describes the planned evolution of **CZar — a semantic authority layer for C**.

The roadmap is structured to:
- keep v0 focused on fundamentals,
- reach a stable and useful v1.0,
- add higher-level abstractions only after the core is solid.

---

## v0.x — Foundations (pre-1.0)

### v0.1 — Pipeline & Identity
**Goal:** CZar exists, runs, and round-trips C.

- `cz` CLI
- Accept `.cz` input
- Invoke system C preprocessor (`cc -E -x c`)
- Parse preprocessed C (C11 baseline)
- Preserve and emit correct `#line` directives
- Strip `#pragma czar ...` from emitted C
- Passthrough behavior for pure C input

---

### v0.2 — Diagnostics, Pragmas, Naming
**Goal:** Precise errors and controllable rules.

- Diagnostic engine (error / warning / note)
- Stable rule IDs
- Scoped pragmas:
  - `#pragma czar safety off|default|strict`
  - `#pragma czar diagnostic <rule>=off|warn|error`
- Naming convention enforcement:
  - globals: `UPPER_SNAKE_CASE`
  - types: `PascalCase`
  - functions / fields: `snake_case`
- Errors by default

---

### v0.3 — Runtime Core
**Goal:** Core CZ runtime exists.

- `cz.h` umbrella header
- `cz_rt`:
  - `FILE`, `LINE`, `FUNC`
  - `cz_assert`, `todo`, `fixme`, `cz_unreachable`
- Monotonic clock:
  - `cz_now_monotonic_ns`
  - `cz_sleep_ns` (+ helpers)

---

### v0.4 — Types, Aliases, Constants
**Goal:** Make C types explicit and safe.

- Built-in aliases:
  - `u8..u64`, `i8..i64`
  - `f32`, `f64`
  - `usize`, `isize`
- Mandatory zero-initialization of locals
- Numeric limit constants:
  - `U8_MIN`, `U8_MAX`, `I32_MIN`, `I32_MAX`, etc.
- Lowering to prefixed C types (`cz_u8`, `CZ_U8_MAX`, …)

---

### v0.5 — Ergonomics: Strings, Slices, Foreach
**Goal:** Safer data handling.

- Built-in `string` → `cz_string`
- Built-in `slice<T>`
- `foreach` loops over strings and slices
- Optional bounds-checking policy

---

### v0.6 — Unsafe & Explicitness
**Goal:** Make danger explicit and greppable.

- `unsafe {}` blocks
- `unsafe_cast(T, expr)`
- `safe_cast(T, expr, fallback)`
- Enforced explicit narrowing casts
- Unsafe usage diagnostics

---

### v0.7 — Logging
**Goal:** Standardized, structured logging.

- `cz_log_*` API
- Log levels and sinks
- Automatic FILE / LINE / FUNC context
- Bounded formatting (no UB)

---

### v0.8 — Semantic Safety Rules
**Goal:** Catch common C bugs early.

- Ignored return values are errors
- `_ = expr;` explicit discard
- Banned dangerous APIs (`gets`, `strcpy`, …)
- Unchecked null dereference detection
- Pointer arithmetic baseline warnings

---

### v0.9 — Methods & Extensions
**Goal:** Structured APIs without inheritance.

- Methods defined by first parameter named `self`
- Method call sugar: `v.len()`
- Extension methods
- Fixed name mangling: `cz_<Type>_<method>`

---

### v0.10 — Named Arguments (Labels Only)
**Goal:** Clear call sites without complexity.

- Named arguments at call sites
- No reordering
- No defaults
- Names must match parameter order
- Variadics excluded

---

### v0.11 — Enums & Exhaustiveness
**Goal:** Eliminate a class of logic bugs.

- CZar enums (closed sets)
- Exhaustive `switch` checking
- `default` allowed only with `cz_unreachable()`

---

### v0.12 — Defer
**Goal:** Deterministic cleanup.

- `defer {}` (block-scoped)
- Executes on scope exit
- Control-flow rewriting for `return`
- `goto` across defer scopes is an error

---

### v0.13 — Polishing & Formatter
**Goal:** Stabilization and usability.

- Improved diagnostics wording
- Stronger null-check dominance analysis
- Mustache-style formatter (runtime)
- Documentation: CZar Reference v0

---

## v1.0 — Stable Release

**Goal:** CZar is stable, documented, and usable on real codebases.

- CLI and diagnostics stabilized
- Runtime API frozen
- Test suite covering GCC / Clang, C11 / C17
- Self-hosting preparation
- Versioned releases

---

## Post-1.0 Features

### v1.1 — Interfaces (`iface`)
**Goal:** Compile-time shape contracts (no runtime).

- `iface` declarations (fields + methods)
- `impl Type : Iface;` conformance assertions
- Structural checking, nominal declaration
- CZar-only feature (no emitted C)
- No runtime interface values

---

### v1.2 — Composition Flattening
**Goal:** Make composition ergonomic without inheritance.

- `embed T;` and `embed T as name;`
- Lowered to real struct members
- Flattened field and method access
- Strict ambiguity diagnostics
- No ABI magic

---

## Explicitly Out of Scope (for now)

- Runtime polymorphic interfaces (vtables)
- Generics / monomorphization
- Garbage collection
- Exceptions
- Language-level modules
- Borrow/lifetime systems

---

## Guiding Principles

- **C stays C**
- **CZar extends C at the source level**
- **Output is always plain C**
- **Unsafe must be explicit**
- **Errors over warnings**
- **No hidden runtime costs**

If you can’t explain the emitted C, it’s a bug.
