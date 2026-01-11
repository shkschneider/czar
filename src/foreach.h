/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Transforms foreach-like syntax to portable C for loops.
 *
 * Supported patterns:
 * - for (type var : collection)        - iterate over collection
 * - for (type idx, type val : array)   - iterate with index and value
 * - for (_, var : collection)          - iterate without explicit index variable
 * - for (type var : start..end)        - range-based iteration
 */

#pragma once

#include "../parser.h"

/* Transform foreach-like loops to standard C for loops */
void transpiler_transform_foreach(ASTNode_t *ast, const char *filename, const char *source);
