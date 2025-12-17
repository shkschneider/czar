# Czar Editor Support

This directory contains editor support files for the Czar programming language.

## Available Editors

### Micro Text Editor

The Micro editor syntax highlighting is available in the `micro/` subdirectory.

**Installation:**
```bash
mkdir -p ~/.config/micro/syntax
cp micro/syntax/czar.yaml ~/.config/micro/syntax/
```

See [micro/README.md](micro/README.md) for detailed installation instructions and features.

## Binary Location

When you build the Czar compiler using `./build.sh`, the resulting `cz` binary will be placed in this `dist/` directory.

```bash
./build.sh
./dist/cz --help
```

## Future Support

Additional editor support may be added in the future, including:
- Emacs
- NeoVim
- VS Code
- Other popular editors

## Contributing

If you'd like to contribute editor support for other editors, please:
1. Create a subdirectory for the editor (e.g., `emacs/`, `neovim/`)
2. Include the syntax/highlighting files
3. Add a README.md with installation instructions
4. Update this main README.md to list the new editor

## Testing Syntax Highlighting

An example Czar file (`micro/example.cz`) is provided to test syntax highlighting features.
