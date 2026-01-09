/*
 * CZar - C semantic authority layer
 * Transpiler deprecated module (transpiler/deprecated.c)
 *
 * Handles #deprecated compiler extension directive.
 * Transforms #deprecated into __attribute__((deprecated)) for GCC/Clang.
 */

#include "cz.h"
#include "deprecated.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Skip whitespace and comments */
static size_t skip_whitespace(ASTNode **children, size_t count, size_t start) {
    for (size_t i = start; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        TokenType type = children[i]->token.type;
        if (type != TOKEN_WHITESPACE && type != TOKEN_COMMENT) {
            return i;
        }
    }
    return count;
}

/* Check if this position is the start of a function declaration/definition */
static int is_function_declaration(ASTNode **children, size_t count, size_t start) {
    size_t i = start;
    int found_identifier = 0;
    int found_open_paren = 0;

    /* Look for pattern: [return_type] identifier ( ... ) */
    while (i < count) {
        if (children[i]->type != AST_TOKEN) {
            i++;
            continue;
        }

        Token *tok = &children[i]->token;

        if (tok->type == TOKEN_WHITESPACE || tok->type == TOKEN_COMMENT) {
            i++;
            continue;
        }

        if (tok->type == TOKEN_IDENTIFIER) {
            found_identifier = 1;
            i++;
            continue;
        }

        if (tok->type == TOKEN_PUNCTUATION) {
            if (tok->length == 1 && tok->text[0] == '(') {
                if (found_identifier) {
                    found_open_paren = 1;
                    break;
                }
            }
        }

        i++;
        
        /* Stop if we hit something that's clearly not a function */
        if (tok->type == TOKEN_PUNCTUATION && 
            (tok->text[0] == ';' || tok->text[0] == '{' || tok->text[0] == '}')) {
            break;
        }
    }

    return found_identifier && found_open_paren;
}

/* Transform #deprecated directives to __attribute__((deprecated)) */
void transpiler_transform_deprecated(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Scan for #deprecated patterns */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        if (ast->children[i]->token.type != TOKEN_PREPROCESSOR) continue;

        Token *tok = &ast->children[i]->token;
        
        /* Check if this is a #deprecated directive */
        if (tok->length < 11 || strncmp(tok->text, "#deprecated", 11) != 0) {
            continue;
        }

        /* Found #deprecated, check if it's followed by a function declaration */
        size_t next_pos = skip_whitespace(ast->children, ast->child_count, i + 1);
        
        if (next_pos >= ast->child_count) {
            /* Just remove the #deprecated if nothing follows */
            free(ast->children[i]->token.text);
            ast->children[i]->token.text = strdup("");
            ast->children[i]->token.length = 0;
            continue;
        }

        /* Check if what follows is a function declaration */
        if (is_function_declaration(ast->children, ast->child_count, next_pos)) {
            /* Replace #deprecated with __attribute__((deprecated)) followed by a space */
            char *replacement = strdup("__attribute__((deprecated)) ");
            if (replacement) {
                free(ast->children[i]->token.text);
                ast->children[i]->token.text = replacement;
                ast->children[i]->token.length = strlen(replacement);
                ast->children[i]->token.type = TOKEN_IDENTIFIER;
            }
        } else {
            /* Not a function, just remove the #deprecated directive */
            free(ast->children[i]->token.text);
            ast->children[i]->token.text = strdup("");
            ast->children[i]->token.length = 0;
        }
    }
}
