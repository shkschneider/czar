/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles inline expansion of TODO() calls without macros.
 */

#pragma once

#include "../parser.h"

/* Expand TODO() calls inline with .cz file location */
void transpiler_expand_todo(ASTNode *ast, const char *filename);
