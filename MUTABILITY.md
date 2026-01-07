# Mutability Feature in CZar

## Overview

CZar implements explicit mutability where **everything is immutable by default**, unlike C where everything is mutable by default. This is achieved through:
- The `mut` keyword to explicitly mark things as mutable
- Automatic `const` insertion for immutable declarations

## Current Implementation (v0.1)

### What Works

1. **Function Parameters (non-pointer types)**
   ```c
   // CZar
   void func(u8 a, mut u8 b) { ... }
   
   // Generated C
   void func(const uint8_t a, uint8_t b) { ... }
   ```

2. **`mut` Keyword Stripping**
   - `mut Type` → `Type` in generated C
   - The `mut` keyword is recognized and removed from the output

### Current Limitations

The following are **not yet implemented** but are planned for future versions:

1. **Local Variables**
   - Currently: Local variables remain mutable (C default)
   - Planned: `u8 x = 5;` → `const uint8_t x = 5;`
   - Rationale: Deferred to avoid breaking existing code

2. **Pointer Types**
   - Currently: Pointers are not handled
   - Planned: `Type *p` → `const Type * const p` (const pointer to const data)
   - Challenge: Requires sophisticated analysis to handle both pointer and pointee mutability

3. **User-Defined Types**
   - Currently: Only built-in types (u8, i32, etc.) get `const`
   - Planned: Struct types should also get `const` treatment
   - Example: `MyStruct s` → `const MyStruct_t s`

4. **Struct Methods**
   - Currently: `self` parameter is automatically mutable (no const)
   - Working as intended: Methods need mutable access to modify struct

## Usage Examples

### Basic Function Parameters
```c
// Immutable parameter (automatically const)
void process(u8 value) {
    // value cannot be modified
    printf("%u\n", value);
}

// Mutable parameter (explicit mut)
void increment(mut u8 value) {
    value = value + 1;  // OK - value is mutable
    printf("%u\n", value);
}
```

### Mixed Parameters
```c
void compute(u8 input, mut u8 output) {
    // input is const, output is mutable
    output = input * 2;
}
```

## Design Philosophy

CZar's mutability feature follows the principle of **safe by default**:
- Immutability prevents accidental modifications
- Mutability must be explicitly declared
- The C compiler enforces these constraints
- No runtime overhead (compile-time only)

## Future Work

1. Extend `const` insertion to local variables
2. Implement pointer mutability (`const Type * const p`)
3. Support user-defined types
4. Add validation/warnings for mutability misuse
5. Consider array element mutability
6. Document interaction with other CZar features (methods, autodereference, etc.)

## Testing

- Test file: `test/mutability_basic.cz`
- All existing tests pass (backward compatible)
- No breaking changes to existing CZar code

## Implementation Notes

- Transformation runs after named arguments processing
- Transformation runs before type name replacements (u8 → uint8_t)
- Uses AST token manipulation to insert/remove keywords
- Conservative approach: only modifies known-safe contexts
