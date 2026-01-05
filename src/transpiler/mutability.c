/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Transforms mutability keywords for C compilation.
 * Strategy: Strip 'mut' keyword only.
 * CZar provides mutability semantics but C doesn't enforce them without const.
 */

#define _POSIX_C_SOURCE 200809L

#include "mutability.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Validate mutability rules - minimal validation */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source) {
    /* For now, just do minimal validation */
    /* Future: could add validation for struct fields having mut, etc. */
    (void)ast;
    (void)filename;
    (void)source;
}

/* Transform mutability keywords: Strip 'mut' keyword only */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) {
        return;
    }

    if (ast->type == AST_TOKEN) {
        /* Remove 'mut' keyword by replacing it with empty string */
        if (ast->token.type == TOKEN_IDENTIFIER &&
            strcmp(ast->token.text, "mut") == 0) {
            free(ast->token.text);
            ast->token.text = strdup("");
            ast->token.length = 0;
        }
    }

    /* Recursively transform children */
    for (size_t i = 0; i < ast->child_count; i++) {
        transpiler_transform_mutability(ast->children[i]);
    }
}
