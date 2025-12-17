# Reserved / Forbidden identifiers

_all case insensitive_

- and: logical and
- any: void*
- assert: abort() if condition is false
- bool / boolean
- clone / copy: clones (on heap) a value
- cz_* _reserved_
- _czar_* _reserved_
- DEBUG: macro to get or set global debug flag
- else
- elseif / elsif: if ... elseif ... else
- f32 / f64: floats
- false
- FILE: macro with the current file name
- fn / fun / func / function
- free: deallocate memory form the heap
- FUNCTION: macro with the current function name
- i8 / i16 / i32 / i64: integers
- if
- import
- is
- main_main _reserved_
- module
- mut / mutable: marks a variable as actually mutable
- new / alloc / stack / heap: new allocates on heap
- null / nil: (void*)0
- or: logical or
- pub / public
- return
- self: pointer to current instance (struct)
- string / cstr: string is a builtin type while cstr is C's char*
- struct: like a C struct but with methods
- true
- typeof / sizeof
- u8 / u16 / u32 / u64: unsigned integers
- void: nothing
- while / for : loops
