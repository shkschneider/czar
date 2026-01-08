/*
 * CZar - C semantic authority layer
 * Member access transformation header (transpiler/autodereference.h)
 *
 * Handles auto-dereference of pointers when using . operator.
 */

#pragma once

#include "../parser.h"

/* Transform member access operators (. to -> for pointers) */
void transpiler_transform_autodereference(ASTNode *ast);
