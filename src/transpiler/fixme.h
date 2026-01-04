/*
 * CZar - C semantic authority layer
 * Transpiler FIXME expansion module (transpiler/fixme.h)
 *
 * Handles inline expansion of FIXME() calls without macros.
 */

#pragma once

#include "../parser.h"

/* Expand FIXME() calls inline with .cz file location */
void transpiler_expand_fixme(ASTNode *ast, const char *filename);
