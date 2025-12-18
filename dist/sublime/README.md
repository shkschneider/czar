# Sublime Text Syntax Highlighting for Czar

This directory contains syntax highlighting support for the Czar programming language in [Sublime Text](https://www.sublimetext.com/).

## Installation

### Option 1: Using Package Control (Future)

Once this syntax is published as a Sublime Text package, you'll be able to install it via Package Control:

1. Open Sublime Text
2. Press `Ctrl+Shift+P` (Windows/Linux) or `Cmd+Shift+P` (macOS) to open the Command Palette
3. Type "Package Control: Install Package" and press Enter
4. Search for "Czar" and install

### Option 2: Manual Installation (Current Method)

#### Automatic Installation Script

**Linux/macOS:**
```bash
# Copy to Sublime Text 3
mkdir -p ~/.config/sublime-text-3/Packages/User
cp czar.sublime-syntax ~/.config/sublime-text-3/Packages/User/

# Or for Sublime Text 4
mkdir -p ~/.config/sublime-text/Packages/User
cp czar.sublime-syntax ~/.config/sublime-text/Packages/User/
```

**Windows:**
```cmd
# Copy to your Sublime Text Packages\User directory
# Default location for Sublime Text 3:
copy czar.sublime-syntax "%APPDATA%\Sublime Text 3\Packages\User\"

# Or for Sublime Text 4:
copy czar.sublime-syntax "%APPDATA%\Sublime Text\Packages\User\"
```

#### Manual Step-by-Step Installation

1. Open Sublime Text

2. From the menu, select:
   - **Preferences → Browse Packages...**
   
   This will open your Packages directory in your file manager.

3. Navigate to the `User` subdirectory (create it if it doesn't exist)

4. Copy `czar.sublime-syntax` to this directory

5. Restart Sublime Text (optional, but recommended)

### Option 3: Project-Specific Installation

You can also place the syntax file in your project's `.sublime` directory:

1. In your Czar project root, create a `.sublime` directory
2. Copy `czar.sublime-syntax` to this directory
3. Sublime Text will use this syntax when you open `.cz` files in this project

## Usage

Once installed, Sublime Text will automatically detect `.cz` files and apply syntax highlighting.

### Setting Syntax Manually

If the syntax isn't automatically detected:

1. Open a `.cz` file
2. Click on the syntax name in the bottom-right corner of the window
3. Select **Czar** from the list

Or use the Command Palette:
1. Press `Ctrl+Shift+P` (Windows/Linux) or `Cmd+Shift+P` (macOS)
2. Type "Set Syntax: Czar" and press Enter

### Setting as Default for .cz Files

To make Czar the default syntax for all `.cz` files:

1. Open a `.cz` file
2. From the menu, select **View → Syntax → Open all with current extension as... → Czar**

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

## Color Schemes

Sublime Text syntax highlighting works with any color scheme. The Czar syntax uses standard TextMate scopes that are supported by all Sublime Text color schemes:

- `keyword.*` - Keywords and control flow
- `storage.type.*` - Type names
- `constant.*` - Constants and literals
- `comment.*` - Comments
- `string.*` - String literals
- `entity.name.function` - Function names
- `variable.parameter` - Function parameters
- `punctuation.*` - Punctuation and delimiters

### Recommended Color Schemes

For the best Czar syntax highlighting experience, try these popular color schemes:

- **Monokai** (default)
- **Mariana**
- **Breakers**
- **Celeste**
- **Sixteen** (various variants)

To change your color scheme:
1. **Preferences → Select Color Scheme...**
2. Choose a color scheme from the list

## Customization

### Creating a Custom Color Scheme

To customize colors specifically for Czar:

1. Create a new color scheme or customize an existing one:
   - **Preferences → Customize Color Scheme...**

2. Add custom rules for Czar scopes. Example:
   ```json
   {
       "name": "Czar Keywords",
       "scope": "keyword.control.czar",
       "foreground": "#F92672"
   }
   ```

3. Save your customizations

### Build System

You can create a build system for Czar in Sublime Text:

1. **Tools → Build System → New Build System...**

2. Add the following (adjust paths as needed):
   ```json
   {
       "cmd": ["/path/to/czar/dist/cz", "run", "$file"],
       "file_regex": "^(..[^:]*):([0-9]+):?([0-9]+)?:? (.*)$",
       "working_dir": "${file_path}",
       "selector": "source.czar"
   }
   ```

3. Save as `Czar.sublime-build`

4. Use `Ctrl+B` (Windows/Linux) or `Cmd+B` (macOS) to build/run Czar files

## Advanced Features

### Code Folding

The syntax definition supports code folding for:
- Function bodies
- Struct definitions
- Comment blocks
- Braced blocks

### Symbol List

Press `Ctrl+R` (Windows/Linux) or `Cmd+R` (macOS) to show the symbol list, which displays:
- Function definitions
- Struct definitions

### Goto Definition

While not built into the syntax file itself, you can use Sublime Text's native Goto Definition features:
- `F12` or right-click → Goto Definition
- Works with indexed symbols in your project

## Troubleshooting

### Syntax highlighting not working

1. **Verify installation**:
   - Open **Preferences → Browse Packages...**
   - Navigate to the `User` folder
   - Verify `czar.sublime-syntax` exists

2. **Restart Sublime Text**:
   - Close and reopen Sublime Text
   - Try opening a `.cz` file again

3. **Check console for errors**:
   - Press `` Ctrl+` `` (Windows/Linux) or `` Cmd+` `` (macOS) to open the console
   - Look for any error messages related to the Czar syntax

4. **Manually set the syntax**:
   - Use the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`)
   - Type "Set Syntax: Czar"

### Colors look wrong

- Try a different color scheme (**Preferences → Select Color Scheme...**)
- Some minimal color schemes may not define all scope colors
- Use a popular color scheme like Monokai or Mariana

### File not recognized as Czar

- The file must have a `.cz` extension
- Manually set the syntax using the steps above
- Set as default for `.cz` files using **View → Syntax → Open all with current extension as...**

## Development

### Modifying the Syntax

To modify the syntax definition:

1. Edit `czar.sublime-syntax` in a text editor
2. The file uses YAML format (version 2)
3. Save changes
4. Restart Sublime Text or reload the syntax:
   - Open the Command Palette
   - Type "Reload Resource" or "Refresh Folder List"

### Testing Changes

1. Open a `.cz` file in Sublime Text
2. Use **View → Show Console** to check for syntax errors
3. Test with various code examples from the Czar test suite

### Syntax Definition Resources

- [Official Sublime Text Syntax Documentation](https://www.sublimetext.com/docs/syntax.html)
- [Scope Naming Guidelines](https://www.sublimetext.com/docs/scope_naming.html)
- [Sublime Text Community Packages](https://github.com/sublimehq/Packages)

## Contributing to Package Control

To make this syntax available via Package Control:

1. Create a GitHub repository for the Czar Sublime Text package
2. Include `czar.sublime-syntax` and package metadata
3. Follow the [Package Control submission guidelines](https://packagecontrol.io/docs/submitting_a_package)
4. Submit the package to Package Control

## More Information

- [Czar Language Repository](https://github.com/shkschneider/czar)
- [Czar Features Documentation](../../FEATURES.md)
- [Czar Semantics Documentation](../../SEMANTICS.md)
- [Sublime Text Documentation](https://www.sublimetext.com/docs/)
- [Package Control](https://packagecontrol.io/)

## Contributing

Contributions to improve the syntax highlighting are welcome! Please submit issues or pull requests to the [Czar repository](https://github.com/shkschneider/czar).

When contributing:
- Test changes with various Czar code examples
- Ensure the syntax follows Sublime Text syntax file conventions
- Update this README if adding new features
- Verify the syntax works with different color schemes
- Include examples demonstrating new patterns

## License

This syntax highlighting definition follows the same license as the Czar programming language.
