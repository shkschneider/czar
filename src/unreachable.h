/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles inline expansion of UNREACHABLE() calls without macros.
 */

#pragma once

#include "../parser.h"

/* Expand UNREACHABLE() calls inline with .cz file location */
void transpiler_expand_unreachable(ASTNode *ast, const char *filename);
