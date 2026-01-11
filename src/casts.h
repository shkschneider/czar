/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles cast validation and transformation.
 */

#pragma once

#include "../parser.h"

/* Validate and transform casts in AST */
void transpiler_validate_casts(ASTNode *ast, const char *filename, const char *source);

/* Transform cast expressions to C equivalents */
void transpiler_transform_casts(ASTNode *ast);
