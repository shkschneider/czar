/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles mutability transformations:
 * - Everything is immutable (const) by default
 * - 'mut' keyword makes things mutable
 * - 'mut' is transitive - applies to both pointer and data
 * - Transform 'mut Type' to 'Type' (strip mut)
 * - Transform 'Type' to 'const Type' (add const)
 */

#pragma once

#include "../parser.h"

/* Transform mutability keywords in AST */
void transpiler_transform_mutability(ASTNode_t *ast, const char *filename, const char *source);
