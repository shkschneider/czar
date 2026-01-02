/*
 * CZar - C semantic authority layer
 * Struct typedef transformation header (transpiler/struct_typedef.h)
 *
 * Handles automatic typedef generation for named structs.
 */

#ifndef TRANSPILER_STRUCT_TYPEDEF_H
#define TRANSPILER_STRUCT_TYPEDEF_H

#include "../parser.h"

/* Transform named struct declarations into typedef structs */
void transpiler_transform_struct_typedef(ASTNode *ast);

#endif /* TRANSPILER_STRUCT_TYPEDEF_H */
