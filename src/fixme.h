/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles inline expansion of FIXME() calls without macros.
 */

#pragma once

#include "../parser.h"

/* Expand FIXME() calls inline with .cz file location */
void transpiler_expand_fixme(ASTNode *ast, const char *filename);
