/*
 * CZar - C semantic authority layer
 * Transpiler enums module (transpiler/enums.h)
 *
 * Handles enum validation and exhaustiveness checking for switch statements.
 * 
 * Scoped enum syntax:
 * - Supports both scoped (EnumName.MEMBER) and unscoped (MEMBER) syntax
 * - Scoped syntax is preferred and recommended
 * - Unscoped syntax generates a warning during transpilation
 * - Scoped syntax is transformed to unscoped for C output
 * 
 * Limitations:
 * - Maximum 256 enum types can be tracked per compilation unit
 * - Maximum 256 members per enum type
 * - Exhaustiveness checking only works for direct enum variable declarations
 * - Does not currently handle typedef'd enums, function parameters, or struct members
 */

#pragma once

#include "../parser.h"

/* Validate enum declarations and switch statements for exhaustiveness */
void transpiler_validate_enums(ASTNode *ast, const char *filename, const char *source);

/* Transform switch statements on enums:
 * - Strips enum prefixes from scoped case labels (EnumName.MEMBER -> MEMBER) */
void transpiler_transform_enums(ASTNode *ast);
