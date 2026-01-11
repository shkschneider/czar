/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Transforms foreach-like syntax to portable C for loops.
 *
 * Supported patterns:
 * - for (type var : start..end)        - range-based iteration (IMPLEMENTED)
 * - for (type idx, type val : array)   - array iteration with index (IMPLEMENTED)
 * - for (_, type val : array)          - array iteration without explicit index (IMPLEMENTED)
 *
 * Planned patterns (TODO):
 * - for (char c : string)              - iterate over string characters
 * - for (type val : array)             - single variable array iteration
 */

#pragma once

#include "../parser.h"

/* Transform foreach-like loops to standard C for loops */
void transpiler_transform_foreach(ASTNode_t *ast, const char *filename, const char *source);
