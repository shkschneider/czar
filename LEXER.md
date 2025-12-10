# Czar Lexer

A lexer (tokenizer) for the Czar programming language, written in Lua.

## Overview

The lexer tokenizes Czar source code (`.cz` files) and produces a stream of tokens that can be consumed by a parser. The lexer is implemented in Lua and designed to work with the Czar-to-C transpiler.

## Features

- **Complete token support**: Keywords, types, operators, identifiers, literals, punctuation
- **Position tracking**: Line and column information for each token
- **Comment handling**: Single-line (`//`) and multi-line (`/* */`) comments
- **Clean API**: Can be used as a library or standalone tool

## Usage

### As a Command-Line Tool

```bash
lua lexer.lua <input.cz>
```

Example:
```bash
lua lexer.lua example.cz
```

This will print all tokens from the input file with their types, values, and positions.

### As a Library

```lua
local Lexer = require("lexer")

-- Read source code
local source = [[
fn main() -> i32 {
    return 0;
}
]]

-- Create lexer and tokenize
local lexer = Lexer.new(source)
local tokens = lexer:tokenize()

-- Process tokens
for _, token in ipairs(tokens) do
    print(token.type, token.value, token.line, token.column)
end
```

## Token Types

### Keywords
- `STRUCT`, `FN`, `RETURN`, `IF`, `ELSE`, `WHILE`, `VAR`, `VAL`

### Built-in Types
- `I32`, `BOOL`, `VOID`

### Literals
- `NUMBER`: Integer literals
- `TRUE`, `FALSE`: Boolean literals
- `NULL`: Null pointer literal

### Identifiers
- `IDENTIFIER`: Variable names, function names, type names

### Operators
- Arithmetic: `PLUS` (+), `MINUS` (-), `STAR` (*), `SLASH` (/), `PERCENT` (%)
- Comparison: `EQEQ` (==), `NE` (!=), `LT` (<), `LE` (<=), `GT` (>), `GE` (>=)
- Logical: `AND` (&&), `OR` (||), `NOT` (!)
- Other: `AMPERSAND` (&), `ARROW` (->), `DOT` (.), `EQ` (=)

### Punctuation
- `LPAREN` ((), `RPAREN` ()), `LBRACE` ({), `RBRACE` (})
- `LBRACKET` ([), `RBRACKET` (])
- `COLON` (:), `SEMICOLON` (;), `COMMA` (,)

### Special
- `EOF`: End of file marker

## Token Structure

Each token is a Lua table with the following fields:

```lua
{
    type = "IDENTIFIER",  -- Token type (see above)
    value = "myVar",      -- The actual text of the token
    line = 1,             -- Line number (1-indexed)
    column = 5            -- Column number (1-indexed)
}
```

## Testing

Run the test suite:

```bash
lua test_lexer.lua
```

The test suite includes:
- Basic token recognition
- Operator parsing
- Identifier and number parsing
- Type keyword recognition
- Punctuation handling
- Comment parsing (line and block)
- Position tracking
- Full `example.cz` file tokenization

## Example

Given this Czar code:

```czar
struct Vec2 {
    x: i32;
    y: i32;
}

fn main() -> i32 {
    var v: Vec2 = Vec2 { x: 3, y: 4 };
    return 0;
}
```

The lexer produces tokens like:

```
1: STRUCT          'struct' at 1:1
2: IDENTIFIER      'Vec2' at 1:8
3: LBRACE          '{' at 1:13
4: IDENTIFIER      'x' at 2:5
5: COLON           ':' at 2:6
6: I32             'i32' at 2:8
...
```

## Architecture

The lexer uses a single-pass scanning approach:

1. **Character-by-character scanning**: Reads source code one character at a time
2. **Token recognition**: Matches character patterns to token types
3. **Position tracking**: Maintains line and column numbers
4. **Comment skipping**: Automatically skips over comments
5. **Whitespace handling**: Ignores whitespace but uses it to track positions

## Integration with Compiler Pipeline

The lexer is the first stage of the Czar compiler pipeline:

```
source.cz
   ↓
lexer.lua        → tokens
   ↓
parser.lua       → AST
   ↓
typechecker.lua  → typed AST
   ↓
c_codegen.lua    → .c output
   ↓
clang/gcc        → binary
```

## Requirements

- Lua 5.3 or later

## License

See the main project LICENSE file.
