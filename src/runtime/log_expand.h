/*
 * CZar - C semantic authority layer
 * Log expansion module header (transpiler/log_expand.h)
 *
 * Handles expansion/instrumentation of Log calls with correct source locations.
 */

#pragma once

#include "../parser.h"

/* Expand Log calls to include correct source location via #line directives */
void transpiler_expand_log_calls(ASTNode *ast, const char *filename);
