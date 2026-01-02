# Zero-Initialization Transpiler Support

## Current Status

The v0.3 runtime includes the type system (`cz_u8`, `cz_i32`, etc.) and constants (`CZ_U8_MAX`, etc.), but **automatic zero-initialization of locals requires transpiler support** which is not yet implemented.

## What Needs to Be Done

The transpiler (`bin/main.c` or future AST-based implementation) needs to:

1. **Parse variable declarations** in `.cz` files
2. **Transform uninitialized declarations** to zero-initialized ones
3. **Preserve already-initialized declarations** as-is

### Example Transformations

Input `.cz` code:
```c
void foo(void) {
    cz_u32 count;           // Uninitialized
    cz_i32 value;           // Uninitialized
    cz_f32 ratio = 0.5f;    // Already initialized - no change
}
```

Should transpile to `.c` code:
```c
void foo(void) {
    cz_u32 count = 0;       // Zero-initialized
    cz_i32 value = 0;       // Zero-initialized
    cz_f32 ratio = 0.5f;    // Unchanged
}
```

## Implementation Strategy

### Phase 1: Simple Text-Based (Current Tool)
The current pass-through implementation in `bin/main.c` could be extended with regex-based pattern matching to:
- Detect variable declarations of CZar types
- Add `= 0` initializers if not present
- This is fragile but gets basic coverage

### Phase 2: AST-Based (Future v0.x)
When the full AST-based parser is implemented:
- Parse declarations into AST nodes
- Analyze initialization status
- Transform AST to add zero-initializers
- Generate correct C output

## Testing Strategy

Tests should verify:
1. Uninitialized locals get zero-initialized
2. Already-initialized locals are unchanged
3. Arrays and structs are zero-initialized correctly
4. Function parameters are NOT zero-initialized (they have caller-provided values)
5. Static and global variables follow C semantics (already zero-initialized)

## Design Notes

From `DESIGN.md`:
> "forced initialization ; zero initialization removes a footgun, not control"

Zero-initialization is:
- **Mandatory** for safety (eliminates undefined behavior)
- **Explicit** in the generated C (no hidden magic)
- **Cost-aware** (developers can see the initialization in output C)
- **Overridable** when needed with explicit initialization

## Related Files

- `src/cz.h` - Type definitions (done)
- `bin/main.c` - Current transpiler (needs enhancement)
- `tests/v0.3_zero_init.cz` - Conceptual test showing expected behavior
- `ROADMAP.md` - v0.4 section describes this feature
