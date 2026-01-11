/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles auto-dereference of pointers when using . operator.
 */

#pragma once

#include "../parser.h"

/* Transform member access operators (. to -> for pointers) */
void transpiler_transform_autodereference(ASTNode *ast);
