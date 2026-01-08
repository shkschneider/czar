/*
 * CZar - C semantic authority layer
 * Transpiler functions module (transpiler/functions.h)
 *
 * Handles function-related transformations and validations.
 */

#pragma once

#include "../parser.h"

/* Validate and transform function declarations */
void transpiler_validate_functions(ASTNode *ast, const char *filename, const char *source);

/* Transform function declarations (main return type, empty parameter lists) */
void transpiler_transform_functions(ASTNode *ast);
