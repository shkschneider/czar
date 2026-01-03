/*
 * CZar - C semantic authority layer
 * Transpiler enums module (transpiler/enums.h)
 *
 * Handles enum validation and exhaustiveness checking for switch statements.
 */

#pragma once

#include "../parser.h"

/* Validate enum declarations and switch statements for exhaustiveness */
void transpiler_validate_enums(ASTNode *ast, const char *filename, const char *source);

/* Transform switch statements on enums to add default: UNREACHABLE() if missing */
void transpiler_transform_enums(ASTNode *ast);
