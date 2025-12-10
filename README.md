# C Is Awesome

> https://www.ibm.com/docs/en/i/7.5.0?topic=extensions-standard-c-library-functions-table-by-name
> http://www.crasseux.com/books/ctutorial/index.html
> https://github.com/oz123/awesome-c

```sh
make -B && make run ; make clean >/dev/null
```

## Standards

> Portable Operating System Interface

- widely supported
- manual memory management is powerful
- no operator overloading is great
- verbose is good for clarity
- throwing exceptions is arguably bad
- portable (with efforts)

**C89**

> ANSI X3.159-1989

**C99**

> ISO/IEC 9899:1999

- inline functions
- single-line comments `//`
- `stdbool.h` `inttypes.h`
- designated initializers `{ . }`

**C11 (c1x)**

> ISO/IEC 9899:2011
> __STDC_VERSION__ 201112L

- unicode: `char16_t`/`char32_t`

**C17**

> ISO/IEC 9899:2018
> __STDC_VERSION__ 201710L

**C23 (c2x)**

> ISO/IEC 9899:2024
> __STDC_VERSION__ 202311L

- `nullptr`/`nullptr_t`
- `bool`: `true`/`false`
- digit separator `'`

## Files

- Headers `.h`
- Sources `.c` -> Object `.o`
- Makefile?

    > Someone had good intentions at each step along the way, but nobody stopped to ask why.

## Compilation

Enable all warnings and treat them as errors: `-Wall -Werror`.

Static executable: `-static`.

The build system / toolchain of C is kinda complicated though:
Makefile, CMake, Meson...

**Step**

- Pre-Processing: macros...
- Compiling: `*.c` -> assembly `.s`
- Assembling: `*.s` -> objects `.o`
- Linking: `*.o` -> executable

## Macros

Macros are powerful but should be limited.

## Data Types

**Pointer**

Memory address of _something_.
Native strings are null-terminated array of `char` (so "string" = `char *`).

**Struct**

Pointer to multiple values (memory-aligned):

- `s = struct { char a, int b } ; s.a` = address `s` offset by 0
- `s = struct { char a, int b } ; s.b` = address `s` offset by 1 (`sizeof(char)`)
- `s = struct { char a, int b, float c } ; s.b` = address `s` offset by 2 (`sizeof(char) + sizeof(int)`)

**Union**

Pointer to only one data from a list of possible types:

- `u = union { char a, int b } ; u.a` = address `u` as `char`
- `u = union { char a, int b } ; u.b` = address `u` as `int`

**Array**

Pointer which can be offset:

- `array[0]` = address `array` offset by 0
- `array[1]` = address `array` offset by 1 (`sizeof(*array) * 1`)
- `array[2]` = address `array` offset by 2 (`sizeof(*array) * 2`)

**List**

Pointer to element that links to other elements.
Like a dynamic array.

- `l = struct { char a, struct *next }`
- `ll = l->next`

**Pair**

Key-Value storage.
Like a Vector(2).

**Map**

List of Key-Value pairs, with unique keys.
Like a dictionary.

**Set**

List of strictly unique items.

**Queue**

First-In First-Out (FIFO) -- rarely Last-In Last-Out (LILO).

**Stack**

Last-In First-Out list (LIFO).

**Custom (examples)**

- Vector2: a pair of X, Y values
- String: a length/capacity struct of chars
- Result: success/failure return values
- ...: only limited by your imagination

## Libraries

- `unique_ptr`/`shared_ptr`: https://github.com/Snaipe/libcsptr
- `arena`:
    - https://github.com/thejefflarson/arena
    - https://github.com/tsoding/arena
- `string`:
    - https://github.com/tsoding/sv
    - https://github.com/maxim2266/str
    - https://github.com/sheredom/utf8.h
- `log`: https://github.com/HardySimpson/zlog
- OOP: https://github.com/small-c/obj.h
- (no)build: https://github.com/tsoding/nob.h
- flags:
    - https://github.com/tsoding/flag.h
    - https://github.com/jibsen/parg
    - https://github.com/docopt/docopt.c
- configuration:
    - https://github.com/libconfuse/libconfuse
    - https://github.com/tjol/ckdl
- extended standard library:
    - https://github.com/tezc/sc
    - https://github.com/srdja/Collections-C
    - https://github.com/LeoVen/C-Macro-Collections
- https://github.com/troglobit/libCello
- script: https://github.com/ryanmjacobs/c
- ...: https://github.com/clibs/clib/wiki/Packages

## Lack of features

Ackchyually...
Yes language is old, but available everywhere, and battle-tested.
Libraries are available for decades which greatly extend the language.

What I'm trying to say is that many downsides of the language can actually, depending on the situation and people involved, be upsides.

What I'm saying is: we should all write more C.

- You need to manually manage your memory, which can appear hard and bug-prone, but done right, is actually very powerful.
- No objects... kinda. Is that a bad thing?
- No packages... prefixes for the win.
