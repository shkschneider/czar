/*
 * CZar - C semantic authority layer
 * Transpiler arguments module (transpiler/arguments.h)
 *
 * Handles named arguments (labels only) transformation.
 * Named arguments allow labeling function arguments for clarity:
 *   my_function(x = 1, y = 2, z = 3)
 * Labels must match parameter names and preserve order.
 * Labels are stripped in emitted C code.
 */

#pragma once

#include "../parser.h"

/* Transform named arguments in function calls by stripping labels */
void transpiler_transform_named_arguments(ASTNode *ast, const char *filename, const char *source);
