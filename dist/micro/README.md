# Micro Editor Syntax Highlighting for Czar

This directory contains syntax highlighting support for the Czar programming language in the [Micro text editor](https://github.com/zyedidia/micro).

## Installation

### Automatic Installation (Recommended)

Copy the syntax file to your Micro configuration directory:

```bash
mkdir -p ~/.config/micro/syntax
cp czar.yaml ~/.config/micro/syntax/
```

### Manual Installation

1. Locate your Micro configuration directory:
   - Linux/macOS: `~/.config/micro/`
   - Windows: `%USERPROFILE%\.config\micro\`

2. Create the `syntax` subdirectory if it doesn't exist:
   ```bash
   mkdir -p ~/.config/micro/syntax
   ```

3. Copy `czar.yaml` to the syntax directory:
   ```bash
   cp czar.yaml ~/.config/micro/syntax/
   ```

## Usage

Once installed, Micro will automatically detect `.cz` files and apply syntax highlighting. 

If you need to manually set the syntax, press `Ctrl+E` to open the command prompt and type:
```
set syntax czar
```

## Features

The syntax highlighting includes:

- **Keywords**: `fn`, `struct`, `if`, `else`, `while`, `for`, `repeat`, `break`, `continue`, `return`, `module`, `import`, `pub`, `mut`, `new`, `free`, etc.
- **Types**: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `f32`, `f64`, `bool`, `void`, `string`, `any`, etc.
- **Operators**: `and`, `or`, `not`, `is`, arithmetic, comparison, and bitwise operators
- **Constants**: `true`, `false`, `null`, numeric literals (decimal, hex, binary, floating-point)
- **Directives**: `#FILE`, `#FUNCTION`, `#DEBUG`, `#assert`, `#log`
- **Cast syntax**: `as<Type>` (e.g., `value as<i32>`)
- **Comments**: Single-line (`//`) and multi-line (`/* */`)
- **Strings**: Double-quoted strings with escape sequences
- **Special markers**: `TODO`, `XXX`, `FIXME`, `NOTE`, `HACK` in comments

## Testing

To test the syntax highlighting:

1. Open a `.cz` file in Micro
2. Verify that keywords, types, and other elements are properly highlighted
3. Try editing to ensure the highlighting updates correctly

## Customization

To customize the colors used for syntax highlighting, you can modify your Micro colorscheme. The syntax file uses standard Micro color groups:

- `statement` - Keywords and control flow
- `type` - Type names
- `constant` - Constants and literals
- `comment` - Comments
- `preproc` - Preprocessor directives
- `special` - Special syntax like casts
- `symbol.operator` - Operators
- `symbol.brackets` - Brackets and parentheses
- `identifier` - Function names
- `todo` - TODO markers

For more information on customizing colors, see the [Micro colors documentation](https://github.com/zyedidia/micro/blob/master/runtime/help/colors.md).

## Troubleshooting

If syntax highlighting isn't working:

1. Verify the file is in the correct location: `~/.config/micro/syntax/czar.yaml`
2. Restart Micro
3. Check that the file has correct permissions (readable)
4. Manually set the syntax with `Ctrl+E` → `set syntax czar`

For more help, see the [Micro documentation](https://github.com/zyedidia/micro/tree/master/runtime/help).
