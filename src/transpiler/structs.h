/*
 * CZar - C semantic authority layer
 * Struct typedef transformation header (transpiler/structs.h)
 *
 * Handles automatic typedef generation for named structs.
 */

#ifndef TRANSPILER_STRUCTS_H
#define TRANSPILER_STRUCTS_H

#include "../parser.h"

/* Transform named struct declarations into typedef structs */
void transpiler_transform_structs(ASTNode *ast);

#endif /* TRANSPILER_STRUCT_TYPEDEF_H */
