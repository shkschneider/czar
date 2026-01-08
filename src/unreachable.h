/*
 * CZar - C semantic authority layer
 * Transpiler unreachable expansion module (transpiler/unreachable.h)
 *
 * Handles inline expansion of UNREACHABLE() calls without macros.
 */

#pragma once

#include "../parser.h"

/* Expand UNREACHABLE() calls inline with .cz file location */
void transpiler_expand_unreachable(ASTNode *ast, const char *filename);
