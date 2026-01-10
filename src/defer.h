/*
 * CZar - C semantic authority layer
 * Transpiler defer module (transpiler/defer.h)
 *
 * Handles defer keyword for scope-exit cleanup using cleanup attribute.
 */

#pragma once

#include "../parser.h"
#include <stdio.h>

/* Transform defer statements to cleanup attribute pattern */
void transpiler_transform_defer(ASTNode *ast);

/* Emit generated defer cleanup functions to output */
void transpiler_emit_defer_functions(FILE *output);
