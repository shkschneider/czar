# CZar

CZar - an empowering semantic and authority layer for C

> Rules, without replacing the kingdom.

_CZar consumes `.cz` files, analyses and rewrites the C AST and emits **portable C11** that you compile with your usual toolchain._

---

## What CZar is (and is not)

**Is**:

- a post-preprocessor, pre-compiler tool
- a C-to-C semantic transformer
- a way to add features to C without changing C
- incrementally adoptable in existing C codebases

**Is Not**:

- is not a new programming language
- a replacement for C
- a macros system
- a compiler backend
- a runtime framework

## Why CZar

C remains unmatched for performance, control, portability and tooling.

What is lack is **not** power, but **structure and ergonomics**.

CZar fills that gap by adding **language features** and **safety checks** while preserving:
- the C syntax
- the C compilation model
- existing build systems
- debuggability (via correct `#line` mapping)

---

## What CZar adds to C

### Language features

- **Methods on structs**
  - First parameter must be `self`
  - Call syntax: `v.len()` -> `cz_MyStruct_len(&s)`
- **Extension methods**
- **`defer {}`**
  - Block-scoped, deterministic cleanup
- **Named arguments** (labels only)
  - Prevent call-site confusion
- **`foreach` loops**
  - Over slices and strings
- **Enums** with exhaustiveness checking

### Built-in types

- Fixed-width integers: `u8..64`, `i8..64`
- Floating types: `f32`, `f64`
- `string` (length-aware)
- `slice` (pointer + length)
- Exposed numeric limits: `U8_MIN/MAX`, ...

### Built-in utilities

- **Standard logger**
  - `cz_log_info`, `cz_log_error`, ...
  - Automatic file / function / line context
- **Monotonic clock**
  - `cz_now_monotonic_ns`
  - `cz_sleep_ns`
- **Arena allocator**
- `assert`, `todo`, `fixme`, `unreachable`, ...

### Safety

- Zero-initialized locals
- Ignored return values are errors
- Detection of unchecked null dereferences
- Explicit `unsafe {}` blocks
- `safe_cast()` / `unsafe_cast()`
- Bans dangerous C APIs
- Enforced naming conventions

---

## Example

```c
#include <cz>

struct Vec2 {
    i32 x
    i32 y
}

i32 Vec2.length(Vec* self) {
    return self.x * self.y;
}

i32 read_value(File* f) {
    assert(f);
    i32 value;
    defer { file_close(f); }
    _ = file_read(f, &value);
    return value;
}
```

This compiles to **plain, readable C** with:
- real methods
- deterministic cleanup
- explicit error handling
- correct source locations

---

## How it works

```
.cz
 | cc -E
.pp.cz
 | cz
.c
 | cc
binary
```

- CZar runs **after** preprocessing
- Macros and includes are already resolved
- CZar rewrites the AST, not text
- Output remains debuggable C

If a `.cz` file contains only valid C, the output is identical!

---

## Status

CZar is **pre-1.0** and under active development.
- Implemented incrementally
- Tested across GCC / Clang and C11 / C17
- Intended to be **self-hosted** by v1.0
APIs and rules may evolve before 1.0.

[ROADMAP](ROADMAP.md)

---

## Philosophy

- C stays C
- Features, not frameworks
- Unsafe must be explicit
- Errors over warnings
- No hidden runtime costs
- Easy to audit
- Easy to remove

If you can't explain the generated C, it's a bug!

[DESIGN](DESIGN.md)

## License

MIT [LICENSE](LICENSE)
