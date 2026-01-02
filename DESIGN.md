# CZar Design Principles

These principles are intentional.
Features that violate them are rejected, even if they are popular or powerful elsewhere.

- deterministic cleanup
- compile-time contracts
- bounds-aware views
- structured APIs
- enforced conentions
- composition only

- unsafe is named, not inferred
- composition over inheritance
- errors by default, discard by intent
- forced initialization ; zero initialization removes a footgun, not control

---

Low-level code doesn't fail because it's "unsafe". It fails because:
- invariants are implicit
- intent is undocumented
- conventions are unenforced

CZar:
- makes invariants checkable
- makes intent visible
- makes conventions executable

It doesn't "protect" you from doing dangerous things, it **forces you to say when you are doing them**.

---

## 1. C stays C

CZar does not replace C.

- CZar operates **post-preprocessor and pre-compiler**
- CZar extends C at the source level
- CZar always emits **plain, portable C**
- The generated code must be readable, debuggabe and tool-friendly

_If the emitted C cannot be understood without CZar, is it a bug!_

## 2. Explicit over clever

CZar favors explicit intent over inference.

- Unsafe operations must be marked explicitely
- Discarding values requires explicit syntax
- Control flow must be visible and local
- No hidden coercions, lifetimes or ownership rules

_CZar refuses to guess. If intent is unclear, it is an error!_

## 3. Authority, not automation

CZar enforces rules; it does not silently fix code.

- Rules are applied consistently
- Violations produce diagnostics
- Escape hatches exist, but must be explicit
- Pragmas change policy, not semantics

_CZar is strict by default and permissive only be intent._

## 4. Zero Magic Runtime

CZar does not rely on hidden runtime mechanisms.

- No garbage collector
- No implicit allocations
- No hidden control flow
- No mandatory runtime dependencies

_All runtime support is explicit, minimal and visible in emitted C._

## 5. Composition over inheritance

CZar rejects inheritance hierarchies.

- Structs compose other structs
- Behavior is added via methods and extensions
- Interfaces (when present) are explicit contracts, not implicit subtyping

_Flattening and delegation are explicit and checkable._

## 6. Errors are better than warnings

Silent failure is worse than loud failure.

- Errors are the default for rule violations
- Warnings are used only when migration or uncertainty is unavoidable
- Ignored results and unchecked operations are errors

_CZar prefers refusing to build over building incorrect code._

## 7. Incremental adoption

CZar must be adoptable in existing C codebases.

- `.cz` files can coexist with `.c`
- Strictness can be increased gradually
- Removing CZar must not corrupt the codebase

_CZar is a toolchain layer, not an ecosystem fork._

## 8. Greppability matters

Code should be searchable and auditable.

- Dangerous constructs are lexically obvious
- Generated symbols are clearly prefixed
- No behavior is hidden behind macros or conventions alone

_If a reviewer cannot find the risky code, the design is wrong!_

## 9. Toolchain compatibility

CZar must cooperate with existing tools.

- Debuggers must work
- Sanitizers must work
- Profilers must work
- Static analyzers must still be useful

_CZar must not obscure the execution model._

## 10. Simplicity is a feature

Complexity is treated as a cost.

- Features must compose cleanly
- Semantics must be exlainable without footnotes
- Implementation complexity is weighted against long-term maintenance

_If a feature cannot be explained clearly, it does not belong in CZar._

---

## Guiding statement

**CZar does not try to make C safe by default. It trieds to make _intent explicit by default_.**

> Long live C!
