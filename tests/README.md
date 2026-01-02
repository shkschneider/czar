# CZar Tests

This directory contains test `.cz` files for the CZar tool.

## Running Tests

To process a test file through the CZar pipeline:

```bash
make process FILE=tests/example.cz
```

This will:
1. Preprocess `example.cz` to `example.pp.cz` using `cc -E`
2. Process `example.pp.cz` to `example.app.c` using the `cz` tool
3. Compile `example.app.c` to the `example.out` binary

## Example

```bash
# Build the cz tool
make all

# Process a test file
make process FILE=tests/hello.cz

# Run the compiled binary
./tests/hello.out
```

## Cleaning

```bash
# Remove build artifacts but keep source files
make clean
```
