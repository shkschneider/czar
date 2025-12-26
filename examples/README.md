# Examples

This directory contains example programs demonstrating various features of the Czar language.

## Basic Examples

- **hello_world.cz** - Simple hello world program
- **fibonacci.cz** - Fibonacci sequence calculator
- **factorial.cz** - Factorial calculation (recursive and iterative)
- **data_structures.cz** - Using arrays, maps, and pairs

## Intermediate Examples

- **linked_list.cz** - Implementation of a linked list
- **string_processing.cz** - String manipulation examples
- **error_handling.cz** - Error-as-value pattern examples
- **memory_management.cz** - Memory allocation and arena allocator

## Advanced Examples

- **generic_functions.cz** - Using primitive generics
- **interface_example.cz** - Interface implementation
- **module_system/** - Multi-file project with modules

## Running Examples

```bash
# Compile and run
./dist/cz run examples/hello_world.cz

# Build executable
./dist/cz build examples/fibonacci.cz -o fib
./fib

# Compile to C (inspect generated code)
./dist/cz compile examples/factorial.cz
cat examples/factorial.c
```

## Learning Path

1. Start with **hello_world.cz** - basics
2. Try **fibonacci.cz** and **factorial.cz** - control flow and functions
3. Explore **data_structures.cz** - built-in collections
4. Study **memory_management.cz** - pointers and allocation
5. Review **error_handling.cz** - error patterns
6. Advanced: **generic_functions.cz** and **interface_example.cz**

## Creating Your Own Examples

Feel free to add more examples! When adding:
1. Keep examples focused on demonstrating specific features
2. Add comments explaining key concepts
3. Ensure examples compile and run successfully
4. Update this README with a description
