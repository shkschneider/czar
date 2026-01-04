/*
 * CZar - C semantic authority layer
 * Centralized Error Definitions (errors.h)
 *
 * All error messages used by the CZar transpiler.
 * Each error has an UPPER_CASE_ID and a descriptive message.
 */

#pragma once

/* Error reporting function */
void cz_error(const char *filename, const char *source, int line, const char *message);

/* Main/CLI Errors */
#define ERR_CANNOT_OPEN_INPUT_FILE "Cannot open input file '%s'"
#define ERR_CANNOT_OPEN_OUTPUT_FILE "Cannot open output file '%s'"
#define ERR_FAILED_TO_SEEK_INPUT_FILE "Failed to seek input file"
#define ERR_FAILED_TO_GET_INPUT_FILE_SIZE "Failed to get input file size"
#define ERR_MEMORY_ALLOCATION_FAILED "Memory allocation failed"
#define ERR_FAILED_TO_PARSE_INPUT "Failed to parse input"

/* Parser Errors */
#define ERR_MEMORY_ALLOCATION_FAILED_IN_AST_NODE "Memory allocation failed in ast_node_add_child"

/* Validation Errors */
#define ERR_VARIABLE_NOT_INITIALIZED "Variable '%s' must be explicitly initialized. CZar requires zero-initialization: %s %s = 0;%s"
#define ERR_VARIABLE_NOT_INITIALIZED_IN_FUNC "[in %s()] Variable '%s' must be explicitly initialized. CZar requires zero-initialization: %s %s = 0;%s"
#define ERR_VARIABLE_NOT_INITIALIZED_MULTI "Variable '%s' must be explicitly initialized. CZar requires zero-initialization"
#define ERR_VARIABLE_NOT_INITIALIZED_MULTI_IN_FUNC "[in %s()] Variable '%s' must be explicitly initialized. CZar requires zero-initialization"

/* Cast Errors */
#define ERR_C_STYLE_CAST_NOT_ALLOWED "Unsafe C-style cast '(%s)' is not allowed. Use cast<%s>(value[, fallback]) instead."
#define ERR_CAST_REQUIRES_TEMPLATE_SYNTAX "cast requires template syntax: cast<Type>(value)"
#define ERR_CAST_REQUIRES_PARENTHESES "cast requires function call syntax with parentheses"
#define ERR_CAST_INVALID_ARG_COUNT "cast requires 1 or 2 arguments: cast<Type>(value[, fallback])"

/* Enum/Switch Errors */
#define ERR_SWITCH_CASE_NO_CONTROL_FLOW "Switch case must have explicit control flow. Use 'break' to end case, 'continue' for fallthrough, or 'return'/'goto' for other control flow."
#define ERR_ENUM_SWITCH_MISSING_DEFAULT "Switch on enum '%s' must have a default case. Add 'default: UNREACHABLE()' if all cases are covered."
#define ERR_ENUM_SWITCH_NOT_EXHAUSTIVE "Non-exhaustive switch on enum '%s': missing case for '%s'. All enum values must be explicitly handled."
#define ERR_ENUM_VALUE_NOT_UPPERCASE "Enum value '%s' in enum '%s' must be ALL_UPPERCASE (e.g., %s)"

/* Named Arguments Errors */
#define ERR_AMBIGUOUS_ARGUMENTS "Ambiguous function call with consecutive same-type parameters without labels. Use named arguments for clarity: %s"

/* Mutability Errors */
#define ERR_IMMUTABLE_ASSIGNMENT "Cannot assign to immutable variable '%s'. Add 'mut' qualifier to make it mutable: mut %s"
#define ERR_IMMUTABLE_MODIFICATION "Cannot modify immutable variable '%s'. Add 'mut' qualifier to make it mutable: mut %s"
#define ERR_FOR_LOOP_IMMUTABLE_COUNTER "For-loop counter '%s' must be mutable. Use: for (mut %s ...)"
#define ERR_STRUCT_FIELD_MUT_QUALIFIER "Struct fields cannot have 'mut' qualifier. Mutability is determined by the struct instance."
#define ERR_IMMUTABLE_STRUCT_FIELD "Cannot modify field of immutable struct '%s'. Add 'mut' qualifier to make it mutable: mut %s"
