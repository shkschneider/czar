/*
 * CZar - C semantic authority layer
 * Transpiler deprecated module (transpiler/deprecated.h)
 *
 * Handles #deprecated compiler extension directive.
 */

#pragma once

#include "../parser.h"

/* Transform #deprecated directives to __attribute__((deprecated)) */
void transpiler_transform_deprecated(ASTNode *ast);
