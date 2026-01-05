/*
 * CZar - C semantic authority layer
 * Struct typedef transformation header (transpiler/structs.h)
 *
 * Handles automatic typedef generation for named structs.
 */

#pragma once

#include "../parser.h"

/* Validate that 'struct Name' is not used outside of definitions */
void transpiler_validate_struct_usage(ASTNode *ast, const char *filename, const char *source);

/* Transform named struct declarations into typedef structs */
void transpiler_transform_structs(ASTNode *ast);

/* Transform struct initialization syntax */
void transpiler_transform_struct_init(ASTNode *ast);
