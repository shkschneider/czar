/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles if-expression validation and transformation.
 */

#pragma once

#include "../parser.h"

/* Transform if-expressions to ternary operators in AST */
void transpiler_transform_ifexpr(ASTNode_t *ast);
