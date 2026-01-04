/*
 * CZar - C semantic authority layer
 * Pragma parser header (transpiler/pragma.h)
 *
 * Parses and handles #pragma czar directives.
 */

#pragma once

#include "../parser.h"

/* Pragma context for storing parsed pragma settings */
typedef struct {
    int debug_mode;  /* 1 = debug on (default), 0 = debug off */
} PragmaContext;

/* Initialize pragma context with defaults */
void pragma_context_init(PragmaContext *ctx);

/* Parse and apply #pragma czar directives from AST */
void transpiler_parse_pragmas(ASTNode *ast, PragmaContext *ctx);
