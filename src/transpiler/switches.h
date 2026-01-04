/*
 * CZar - C semantic authority layer
 * Transpiler switches module (transpiler/switches.h)
 *
 * Handles generic switch statement transformations and validation.
 */

#pragma once

#include "../parser.h"

/* Validate switch case control flow (each case must have explicit control flow) */
void transpiler_validate_switch_case_control_flow(ASTNode *ast, const char *filename, const char *source);

/* Transform continue in switch cases to fallthrough attributes */
void transpiler_transform_switch_continue_to_fallthrough(ASTNode *ast);

/* Insert default cases into switches that lack them */
void transpiler_insert_switch_default_cases(ASTNode *ast, const char *filename);
