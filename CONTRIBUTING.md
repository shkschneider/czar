# Contributing to Czar

Thank you for your interest in contributing to Czar! This document provides guidelines for contributing to the project.

## Getting Started

### Prerequisites

- LuaJIT (2.1+)
- C toolchain (gcc/clang, make)
- Git

### Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/shkschneider/czar.git
cd czar

# Install dependencies (Debian/Ubuntu)
sudo apt install -y luajit libluajit-5.1-dev build-essential

# Build the compiler
./build.sh

# Run tests
./check.sh
```

## Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/my-feature
# or
git checkout -b fix/my-bugfix
```

### 2. Make Changes

- Keep changes focused and atomic
- Follow existing code style
- Add tests for new features
- Update documentation as needed

### 3. Test Your Changes

```bash
# Build the compiler
./build.sh

# Run full test suite
./check.sh

# Run specific tests
./check.sh tests/ok/my_feature*.cz

# Test your changes manually
./dist/cz build examples/my_example.cz
./examples/my_example.out
```

### 4. Commit

```bash
git add .
git commit -m "feat: add feature X"
# or
git commit -m "fix: resolve issue with Y"
```

#### Commit Message Convention

Use conventional commits format:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `test:` - Adding or updating tests
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `chore:` - Maintenance tasks

### 5. Push and Create PR

```bash
git push origin feature/my-feature
```

Then create a Pull Request on GitHub.

## Code Style

### Lua Code (Compiler)

- Use 4 spaces for indentation
- Follow existing patterns in the codebase
- Keep functions focused and small
- Add comments for complex logic
- Use descriptive variable names

Example:
```lua
-- Parse a binary expression
function Parser:parse_binary_expr(lhs, min_precedence)
    while self:match_binary_op() do
        local op = self:current()
        -- ... parsing logic
    end
    return lhs
end
```

### Czar Code (Language)

Follow the style in existing tests:
- Use 4 spaces for indentation
- Explicit types for variables
- Clear, descriptive names
- Comments for non-obvious code

Example:
```czar
// Calculate factorial recursively
fn factorial(i32 n) i32 {
    if n <= 1 {
        return 1
    }
    return n * factorial(n - 1)
}
```

## Adding Language Features

### 1. Design Phase

- Document the feature in an issue
- Discuss syntax and semantics
- Consider interactions with existing features
- Get feedback from maintainers

### 2. Implementation

Language features typically require changes to:

1. **Lexer** (`src/lexer/init.lua`)
   - Add new tokens if needed
   
2. **Parser** (`src/parser/*.lua`)
   - Add syntax parsing
   - Build AST nodes
   
3. **Type Checker** (`src/typechecker/*.lua`)
   - Add type checking logic
   - Validate semantics
   
4. **Code Generator** (`src/codegen/*.lua`)
   - Generate C code
   
5. **Builtins/Macros** (if applicable)
   - `src/builtins.lua` or `src/macros.lua`

### 3. Testing

Add comprehensive tests:
- `tests/ok/feature_basic.cz` - Basic usage
- `tests/ok/feature_comprehensive.cz` - Complete coverage
- `tests/ok/feature_edge_cases.cz` - Edge cases
- `tests/ko/feature_error_*.cz` - Error conditions

### 4. Documentation

Update:
- `FEATURES.md` - List the new feature
- `SEMANTICS.md` - Add reserved keywords if any
- `README.md` - Update examples if relevant
- `tests/README.md` - Document test coverage

## Testing Guidelines

See [TESTING.md](TESTING.md) for detailed testing guidelines.

### Running Tests

```bash
# All tests
./check.sh

# Specific category
./check.sh tests/ok/string*.cz
./check.sh tests/ko/*.cz

# Single test
./check.sh tests/ok/arithmetic.cz
```

### Writing Tests

1. Every feature needs positive and negative tests
2. Test edge cases and error conditions
3. Keep tests focused and minimal
4. Add clear comments
5. Ensure deterministic behavior

## Debugging

### Debug the Compiler

Add debug prints in Lua:
```lua
print("DEBUG: token = " .. tostring(token.type))
io.stderr:write("Error at line " .. token.line .. "\n")
```

### Debug Generated Code

```bash
# Generate C code
./dist/cz compile tests/ok/mytest.cz

# View generated C
cat tests/ok/mytest.c

# Compile with debug symbols
gcc -g tests/ok/mytest.c -o mytest.out

# Debug with gdb
gdb mytest.out
```

### Enable Debug Mode

```bash
./dist/cz build tests/ok/mytest.cz --debug
./tests/ok/mytest.out
```

## Project Structure

```
czar/
├── src/
│   ├── lexer/          # Tokenization
│   ├── parser/         # AST construction
│   ├── typechecker/    # Type checking and validation
│   ├── lowering/       # AST transformations
│   ├── analysis/       # Static analysis
│   ├── codegen/        # C code generation
│   ├── bin/            # CLI commands
│   ├── std/            # Standard library
│   ├── builtins.lua    # Built-in types and functions
│   ├── macros.lua      # Macro handling
│   ├── errors.lua      # Error reporting
│   └── warnings.lua    # Warning system
├── tests/
│   ├── ok/             # Positive tests
│   ├── ko/             # Negative tests
│   └── fail/           # WIP/Known issues
├── .github/
│   ├── workflows/      # CI/CD
│   └── actions/        # Reusable actions
├── build.sh            # Build script
├── check.sh            # Test runner
├── clean.sh            # Cleanup script
└── stats.sh            # Code statistics
```

## Compiler Pipeline

1. **Lexer**: Source code → Tokens
2. **Parser**: Tokens → AST (Abstract Syntax Tree)
3. **Type Checker**: AST → Validated AST
4. **Lowering**: AST → Simplified AST
5. **Analysis**: Static analysis passes
6. **Code Generator**: AST → C code
7. **C Compiler**: C code → Binary

## Common Tasks

### Add a New Built-in Function

1. Add to `src/builtins.lua`
2. Implement in C (if needed)
3. Add tests in `tests/ok/`
4. Update `FEATURES.md`

### Add a New Operator

1. Add token in `src/lexer/init.lua`
2. Add parsing in `src/parser/expressions.lua`
3. Add type checking in `src/typechecker/inference/expressions.lua`
4. Add codegen in `src/codegen/expressions/operators.lua`
5. Add tests

### Fix a Bug

1. Create a test that reproduces the bug
2. Fix the issue
3. Verify the test passes
4. Run full test suite
5. Submit PR with test and fix

## Review Process

Pull requests will be reviewed for:
- Code quality and style
- Test coverage
- Documentation updates
- Breaking changes
- Performance impact

## Community

- **Issues**: Report bugs or suggest features
- **Discussions**: Ask questions or discuss ideas
- **Pull Requests**: Contribute code or documentation

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## Questions?

If you have questions:
1. Check existing documentation
2. Search closed issues
3. Open a new issue
4. Tag maintainers for urgent matters

Thank you for contributing to Czar! 🎉
