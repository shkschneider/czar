/*
 * CZar - C semantic authority layer
 * Struct typedef transformation header (transpiler/structs.h)
 *
 * Handles automatic typedef generation for named structs.
 */

#pragma once

#include "../parser.h"

/* Transform named struct declarations into typedef structs */
void transpiler_transform_structs(ASTNode *ast);
