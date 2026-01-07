/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.h)
 *
 * Handles mutability transformations:
 * - Everything is immutable (const) by default
 * - 'mut' keyword makes things mutable
 * - Transform 'mut Type' to 'Type' (strip mut)
 * - Transform 'Type' to 'const Type' (add const)
 */

#pragma once

#include "../parser.h"

/* Transform mutability keywords in AST */
void transpiler_transform_mutability(ASTNode *ast, const char *filename, const char *source);
