/*
 * CZar - C semantic authority layer
 * Transpiler TODO expansion module (transpiler/todo.h)
 *
 * Handles inline expansion of TODO() calls without macros.
 */

#pragma once

#include "../parser.h"

/* Expand TODO() calls inline with .cz file location */
void transpiler_expand_todo(ASTNode *ast, const char *filename);
