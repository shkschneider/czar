/*
 * CZar - C semantic authority layer
 * Struct typedef transformation header (transpiler/structs.h)
 *
 * Handles automatic typedef generation for named structs.
 * Also tracks struct names for transformation.
 */

#pragma once

#include "../parser.h"

/* Struct name registry functions */
/* Add a struct name to the registry */
void struct_names_add(const char *name);

/* Check if a name is a registered struct and return the typedef name */
const char *struct_names_get_typedef(const char *name);

/* Clear all registered struct names */
void struct_names_clear(void);

/* Validate that 'struct Name' is not used outside of definitions */
void transpiler_validate_struct_usage(ASTNode *ast, const char *filename, const char *source);

/* Transform named struct declarations into typedef structs */
void transpiler_transform_structs(ASTNode *ast);

/* Transform struct initialization syntax */
void transpiler_transform_struct_init(ASTNode *ast);
