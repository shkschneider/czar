/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles function-related transformations and validations.
 */

#pragma once

#include "../parser.h"

/* Validate and transform function declarations */
void transpiler_validate_functions(ASTNode *ast, const char *filename, const char *source);

/* Transform function declarations (main return type, empty parameter lists) */
void transpiler_transform_functions(ASTNode *ast);

/* Add warn_unused_result attribute to non-void functions */
void transpiler_add_warn_unused_result(ASTNode *ast);

/* Add pure attribute to functions with no parameters or only immutable parameters */
void transpiler_add_pure(ASTNode *ast);
