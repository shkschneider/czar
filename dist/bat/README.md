# Bat Syntax Highlighting for Czar

This directory contains syntax highlighting support for the Czar programming language in [bat](https://github.com/sharkdp/bat), a cat clone with wings.

## Installation

### Option 1: Using bat's Configuration Directory (Recommended)

1. Locate your bat configuration directory:
   - Linux/macOS: `~/.config/bat/`
   - Windows: `%APPDATA%\bat\`

2. Create the `syntaxes` subdirectory if it doesn't exist:
   ```bash
   mkdir -p "$(bat --config-dir)/syntaxes"
   ```

3. Copy the syntax file to bat's configuration directory:
   ```bash
   cp czar.sublime-syntax "$(bat --config-dir)/syntaxes/"
   ```

4. Rebuild bat's cache:
   ```bash
   bat cache --build
   ```

5. Verify the installation:
   ```bash
   bat --list-languages | grep Czar
   ```
   You should see "Czar" listed with the `.cz` file extension.

### Option 2: Manual Installation

1. Find your bat configuration directory:
   ```bash
   bat --config-dir
   ```

2. Navigate to the configuration directory and create the `syntaxes` folder:
   ```bash
   cd $(bat --config-dir)
   mkdir -p syntaxes
   ```

3. Copy `czar.sublime-syntax` into the `syntaxes` directory:
   ```bash
   cp /path/to/czar.sublime-syntax syntaxes/
   ```

4. Build the cache:
   ```bash
   bat cache --build
   ```

### Option 3: Contributing to bat Project

If you'd like to contribute this syntax to the bat project itself:

1. Fork the [bat repository](https://github.com/sharkdp/bat)
2. Add `czar.sublime-syntax` to `assets/syntaxes/02_Extra/` in the bat source tree
3. Run `assets/create.sh` to rebuild the syntax cache
4. Create a pull request

**Note:** Do not include the regenerated `syntaxes.bin` file in pull requests. The bat maintainers will update it before releases.

## Usage

Once installed, bat will automatically detect `.cz` files and apply syntax highlighting:

```bash
bat hello_world.cz
bat path/to/czar_file.cz
```

You can also explicitly specify the Czar syntax:

```bash
bat -l Czar some_file
bat --language=Czar some_file
```

To view available languages:

```bash
bat --list-languages
```

## Features

The syntax highlighting includes comprehensive support for:

### Keywords
- **Control flow**: `if`, `else`, `elseif`, `elsif`, `while`, `for`, `repeat`, `break`, `continue`, `return`, `in`
- **Declarations**: `fn`, `struct`, `module`, `import`, `pub`, `mut`, `new`, `free`, `type`
- **Operators**: `and`, `or`, `not`, `is`, `self`, `sizeof`

### Types
- **Integers**: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`
- **Floats**: `f32`, `f64`
- **Other**: `bool`, `void`, `string`, `cstr`, `any`
- **Collections**: `pair`, `array`, `map`
- **Custom types**: Capitalized identifiers (e.g., `Point`, `Rect`)

### Literals
- **Boolean**: `true`, `false`
- **Null**: `null`, `nil`
- **Numbers**: 
  - Decimal: `123`, `1_000_000`
  - Hexadecimal: `0xFF`, `0x1A2B`
  - Binary: `0b1010`, `0b1111_0000`
  - Float: `3.14`, `1.5e-10`

### Special Syntax
- **Directives**: `#FILE`, `#FUNCTION`, `#LINE`, `#DEBUG`, `#assert`, `#log`
- **Cast syntax**: `as<Type>` (e.g., `value as<i32>`)
- **Method calls**: `object:method()`
- **Generic types**: `array<i32>`, `map<string:i32>`

### Comments
- **Single-line**: `//` 
- **Multi-line**: `/* ... */`
- **TODO markers**: `TODO`, `XXX`, `FIXME`, `NOTE`, `HACK` (highlighted in comments)

### Strings
- Double-quoted strings with escape sequences
- Escape sequences: `\"`, `\'`, `\n`, `\r`, `\t`, `\\`, `\xHH`, `\uHHHH`, `\UHHHHHHHH`

## Example

Here's a sample Czar program with syntax highlighting:

```czar
// Example: Rectangle area calculation
struct Point {
    i32 x
    i32 y
}

struct Rect {
    Point top_left
    u32 width
    u32 height
}

fn Rect:area() u64 {
    u64 w = self.width as<u64>
    u64 h = self.height as<u64>
    return w * h
}

fn main() i32 {
    Rect r = Rect {
        top_left: Point { x: 0, y: 0 },
        width: 10 as<u32>,
        height: 5 as<u32>
    }
    
    u64 a = r:area()
    #log("Area:", a)
    
    return 0
}
```

## Troubleshooting

### Syntax highlighting not working

1. **Verify installation**:
   ```bash
   bat --list-languages | grep -i czar
   ```
   If Czar is not listed, the syntax file may not be properly installed.

2. **Check file location**:
   ```bash
   ls "$(bat --config-dir)/syntaxes/czar.sublime-syntax"
   ```
   The file should exist at this location.

3. **Rebuild cache**:
   ```bash
   bat cache --build
   ```
   This regenerates bat's syntax cache.

4. **Clear cache and rebuild**:
   ```bash
   bat cache --clear
   bat cache --build
   ```

5. **Check bat version**:
   ```bash
   bat --version
   ```
   Ensure you're using a recent version of bat (0.18.0 or later recommended).

### File extension not recognized

If bat doesn't recognize `.cz` files automatically, you can:

1. Explicitly specify the language:
   ```bash
   bat -l Czar file.cz
   ```

2. Add an alias to your shell configuration:
   ```bash
   alias batcz='bat -l Czar'
   ```

### Syntax appears incorrect

The syntax highlighting is based on the Czar language specification. If you notice issues:

1. Verify the syntax is valid Czar code
2. Check if you're using newer language features not yet in the syntax file
3. Report issues to the Czar repository

## Customization

Bat uses color themes for syntax highlighting. To customize colors:

1. View available themes:
   ```bash
   bat --list-themes
   ```

2. Set a theme:
   ```bash
   bat --theme="Monokai Extended" file.cz
   ```

3. Make it permanent by adding to your bat config file (`$(bat --config-dir)/config`):
   ```
   --theme="Monokai Extended"
   ```

The Czar syntax uses standard TextMate scopes that work with all bat themes:
- `keyword.*` - Keywords and control flow
- `storage.type.*` - Type names
- `constant.*` - Constants and literals
- `comment.*` - Comments
- `string.*` - String literals
- `entity.name.function` - Function names
- `variable.parameter` - Function parameters

## More Information

- [Czar Language Repository](https://github.com/shkschneider/czar)
- [Czar Features Documentation](../../FEATURES.md)
- [Czar Semantics Documentation](../../SEMANTICS.md)
- [bat Documentation](https://github.com/sharkdp/bat)
- [Sublime Text Syntax Documentation](https://www.sublimetext.com/docs/syntax.html)

## Contributing

Contributions to improve the syntax highlighting are welcome! Please submit issues or pull requests to the [Czar repository](https://github.com/shkschneider/czar).

When contributing:
- Test changes with various Czar code examples
- Ensure the syntax follows Sublime Text syntax file conventions
- Update this README if adding new features
- Verify the syntax works with different bat themes
