# CZar Source

This directory will contain the implementation of the CZar semantic analysis and transformation engine.

Currently, the `cz` tool is a simple pass-through that copies input to output without any processing. Future implementations will add:

- Lexing and parsing of preprocessed C code
- AST construction and analysis
- Semantic transformations (methods on structs, defer blocks, etc.)
- Code generation with proper `#line` directives for debugging

The tool is built from `bin/main.c` which provides the command-line interface and file handling.
