/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles automatic typedef generation for named structs.
 */

#pragma once

#include "../parser.h"

/* Transform named struct declarations into typedef structs */
void transpiler_transform_structs(ASTNode *ast);

/* Transform struct initialization syntax */
void transpiler_transform_struct_init(ASTNode *ast);

/* Replace all uses of struct names with their _t variants */
void transpiler_replace_struct_names(ASTNode *ast);
