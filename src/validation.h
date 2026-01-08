/*
 * CZar - C semantic authority layer
 * Transpiler validation module (transpiler/validation.h)
 *
 * Validates CZar semantic rules and reports errors.
 */

#pragma once

#include "../parser.h"

/* Validate AST for CZar semantic rules */
void transpiler_validate(ASTNode *ast, const char *filename, const char *source);
