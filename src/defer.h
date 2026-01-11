/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles defer keyword for scope-exit cleanup using cleanup attribute.
 */

#pragma once

#include "../parser.h"
#include <stdio.h>

/* Transform defer statements to cleanup attribute pattern */
void transpiler_transform_defer(ASTNode_t *ast);

/* Emit generated defer cleanup functions to output */
void transpiler_emit_defer_functions(FILE *output);
