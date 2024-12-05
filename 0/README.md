# 0 - C-like

## DONE

- statically linked
- standard library
- extended library
- types: bit byte, i8 i16 i32 i64, u8 u16 u32 u64, f8 f16 f32 f64, any
- unused, nothing
- defer: autofree autoclose autofclose
- unused, file, line, function, todo
- string helpers

## TODO

- not eq lt le gt ge ls rs and or -> ! == < <= > >= << >> && ||
- [0-9]_[0-9] -> [0-9]'[0-9]
- foreach
- if cond {} -> if (cond) {}
- myalias :: u8 -> typedef u8 myalias
- main :: function (...) int -> int main(...)
- mystruct :: struct {} -> typedef struct mystruct {}
- myenum :: enum {} -> enum myenum {}
- x := ... -> auto x = ...
- import("whatever", param...) -> import "whatever" + whatever.init(param...)
- string struct (sized, not 0-terminated)
- helper library: string, defer...
- (true) defer -> defer(); return;
- array ([...])
