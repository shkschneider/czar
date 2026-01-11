/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Validates CZar semantic rules and reports errors.
 */

#pragma once

#include "../parser.h"

/* Validate AST for CZar semantic rules */
void transpiler_validate(ASTNode *ast, const char *filename, const char *source);
