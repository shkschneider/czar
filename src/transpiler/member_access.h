/*
 * CZar - C semantic authority layer
 * Member access transformation header (transpiler/member_access.h)
 *
 * Handles auto-dereference of pointers when using . operator.
 */

#ifndef TRANSPILER_MEMBER_ACCESS_H
#define TRANSPILER_MEMBER_ACCESS_H

#include "../parser.h"

/* Transform member access operators (. to -> for pointers) */
void transpiler_transform_member_access(ASTNode *ast);

#endif /* TRANSPILER_MEMBER_ACCESS_H */
