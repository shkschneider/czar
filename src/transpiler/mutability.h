/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.h)
 *
 * Validates mutability rules and tracks mutable/immutable variables.
 */

#pragma once

#include "../parser.h"

/* Validate mutability rules in the AST */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source);

/* Transform mutability keywords (strip 'mut', add 'const' for immutable) */
void transpiler_transform_mutability(ASTNode *ast);
