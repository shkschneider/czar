# CZar

CZar - an empowering semantic and authority layer for C

> Rules, without replacing the kingdom.

_CZar consumes `.cz` files, analyses and rewrites the C AST and emits **portable** C11/POSIX.1‑2008 that you compile with your usual toolchain._

## Why

Low-level code doesn't fail because it's "unsafe". It fails because:
- invariants are implicit
- intent is undocumented
- conventions are unenforced
- _and some things are actually unsafe, alright..._

CZar:
- explicit over clever
- authority, not automation
- zero magic runtime & no macros
- composition & syntax sugar
- errors are better than warnings
- incremental (and reversable) adoption
- simplicity is a feature

## What It Is

- a C-to-C semantic transformer
- a way to add features to C without changing C
- incrementally adoptable in existing C codebases
- reversible

**It is NOT:**

- a new programming language / replacement / "C-killer"
- a macros system
- a compiler backend
- a runtime framework

## How It Works

```
.cz -> .cz.c -> cc ...
```

---

## Language Features

- Explicit **mutability** (`const` by default) & no more `t const *p` vs `t * const p`)
- **Modules** (`#import`)
- `defer`
- Clear **visibility** (private by default)
- Struct **methods** (with `self`)
- Pointer **auto-dereference**
- **Safer** `cast<Type>(value[, fallback])`
- Number & binary literals: `1_000_000`, `0b01010101`
- Concise **types** `i8/16/32/64`, `u8/16/32/64`, `f16/32`, `bool`
- **Enums** with mandatory exhaustiveness
- Standardizes compiler extensions like `unused`, `deprecated`...
- Named arguments
- ...

### Safety

- Mandatory **initialization**
- **Zeroed** structs
- Ignored **return values** are errors (can be ignore with `_`)
- Detection of **unchecked** null dereferences
- Bans dangerous C APIs
- Enforced naming conventions
- Mutability

---

## Status

CZar is **pre-1.0** and under active development.
- Implemented incrementally
- Tested across GCC / Clang and C11 / C17
- Intended to be **self-hosted** by v1.0
APIs and rules may evolve before 1.0.

## License

MIT [LICENSE](LICENSE)

---

> Long live C!
