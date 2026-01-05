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

/* Transform mutability keywords: Strip 'mut' keyword and following whitespace */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) {
        return;
    }

    if (ast->type == AST_TRANSLATION_UNIT) {
        /* Process all children looking for 'mut' keyword */
        for (size_t i = 0; i < ast->child_count; i++) {
            if (ast->children[i]->type == AST_TOKEN) {
                Token *token = &ast->children[i]->token;
                
                /* Remove 'mut' keyword by replacing it with empty string */
                if (token->type == TOKEN_IDENTIFIER &&
                    strcmp(token->text, "mut") == 0) {
                    free(token->text);
                    token->text = strdup("");
                    token->length = 0;
                    
                    /* Also remove the following whitespace token to avoid double spaces */
                    if (i + 1 < ast->child_count &&
                        ast->children[i + 1]->type == AST_TOKEN &&
                        ast->children[i + 1]->token.type == TOKEN_WHITESPACE) {
                        Token *ws_token = &ast->children[i + 1]->token;
                        free(ws_token->text);
                        ws_token->text = strdup("");
                        ws_token->length = 0;
                    }
                }
            }
        }
    }

    /* Recursively transform children */
    for (size_t i = 0; i < ast->child_count; i++) {
        transpiler_transform_mutability(ast->children[i]);
    }
}
