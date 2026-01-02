/*
 * CZar - C semantic authority layer
 * Member access transformation header (transpiler/autodereference.h)
 *
 * Handles auto-dereference of pointers when using . operator.
 */

#ifndef TRANSPILER_AUTODEREFERENCE_H
#define TRANSPILER_AUTODEREFERENCE_H

#include "../parser.h"

/* Transform member access operators (. to -> for pointers) */
void transpiler_transform_autodereference(ASTNode *ast);

#endif /* TRANSPILER_AUTODEREFERENCE_H */
