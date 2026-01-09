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

/* Directive name */
#define DEPRECATED_DIRECTIVE "#deprecated"
#define DEPRECATED_DIRECTIVE_LEN 11

/* Replacement attribute */
#define ATTRIBUTE_DEPRECATED "__attribute__((deprecated))\n"

/* Helper to clear token text (emit function handles NULL text) */
static void clear_token_text(Token *token) {
    if (!token) return;
    free(token->text);
    token->text = NULL;
    token->length = 0;
}

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
            if (tok->length == 1 && tok->text && tok->text[0] == '(') {
                if (found_identifier) {
                    found_open_paren = 1;
                    break;
                }
            }
            /* Stop if we hit something that's clearly not a function */
            if (tok->text && (tok->text[0] == ';' || tok->text[0] == '{' || tok->text[0] == '}')) {
                break;
            }
        }

        i++;
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

        /* Check if this is a #deprecated directive (exact match or followed by whitespace/newline) */
        if (!tok->text ||
            tok->length < DEPRECATED_DIRECTIVE_LEN ||
            strncmp(tok->text, DEPRECATED_DIRECTIVE, DEPRECATED_DIRECTIVE_LEN) != 0) {
            continue;
        }

        /* Ensure it's exactly #deprecated, not #deprecated_something */
        if (tok->length > DEPRECATED_DIRECTIVE_LEN) {
            char next_char = tok->text[DEPRECATED_DIRECTIVE_LEN];
            /* Only accept if followed by whitespace or end of line */
            if (next_char != ' ' && next_char != '\t' && next_char != '\r' && next_char != '\n') {
                continue;
            }
        }

        /* Found #deprecated, check if it's followed by a function declaration */
        size_t next_pos = skip_whitespace(ast->children, ast->child_count, i + 1);

        if (next_pos >= ast->child_count) {
            /* Just remove the #deprecated if nothing follows */
            clear_token_text(&ast->children[i]->token);
            continue;
        }

        /* Check if what follows is a function declaration */
        if (is_function_declaration(ast->children, ast->child_count, next_pos)) {
            /* Replace #deprecated with __attribute__((deprecated)) followed by a space */
            char *replacement = strdup(ATTRIBUTE_DEPRECATED);
            if (replacement) {
                free(ast->children[i]->token.text);
                ast->children[i]->token.text = replacement;
                ast->children[i]->token.length = strlen(replacement);
                /* Change to TOKEN_KEYWORD so it's treated as part of the function declaration */
                ast->children[i]->token.type = TOKEN_KEYWORD;
            } else {
                /* If strdup fails, clear the token to avoid inconsistent state */
                clear_token_text(&ast->children[i]->token);
            }
        } else {
            /* Not a function, just remove the #deprecated directive */
            clear_token_text(&ast->children[i]->token);
        }
    }
}
