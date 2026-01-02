/*
 * CZar - C semantic authority layer
 * Cast handling header (transpiler/casts.h)
 *
 * Handles cast validation and transformation.
 */

#pragma once

#include "../parser.h"

/* Validate and transform casts in AST */
void transpiler_validate_casts(ASTNode *ast, const char *filename, const char *source);

/* Transform cast expressions to C equivalents */
void transpiler_transform_casts(ASTNode *ast);
