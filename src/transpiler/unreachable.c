/*
 * CZar - C semantic authority layer
 * Transpiler unreachable expansion module (transpiler/unreachable.c)
 *
 * Handles inline expansion of UNREACHABLE() calls without macros.
 * Replaces UNREACHABLE("msg") with direct fprintf+abort using .cz file location.
 */

#include "../cz.h"
#include "unreachable.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Check if token text matches */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) return 0;
    return strcmp(token->text, text) == 0;
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

/* Extract string content from a string token (removes quotes) */
static char *extract_string_content(const char *str_with_quotes) {
    if (!str_with_quotes) return NULL;

    size_t len = strlen(str_with_quotes);
    if (len < 2) return NULL;

    /* Remove surrounding quotes */
    char *result = malloc(len - 1);
    if (!result) return NULL;

    strncpy(result, str_with_quotes + 1, len - 2);
    result[len - 2] = '\0';
    return result;
}

/* Find the function name containing this position */
static const char *find_function_name(ASTNode **children, size_t count, size_t current_pos) {
    int brace_depth = 0;
    const char *function_name = NULL;

    /* Scan from start to find which function we're in */
    for (size_t i = 0; i < current_pos && i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *tok = &children[i]->token;

        if (tok->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(tok, "{")) {
                brace_depth++;
                /* If brace_depth is 1, we just entered a top-level block (likely a function) */
                /* Look back for function name pattern: identifier ( ... ) { */
                if (brace_depth == 1) {
                    for (int j = (int)i - 1; j >= 0 && j >= (int)i - 30; j--) {
                        if (children[j]->type == AST_TOKEN &&
                            children[j]->token.type == TOKEN_IDENTIFIER) {
                            /* Check if followed by ( */
                            size_t k = j + 1;
                            while (k < i && children[k]->type == AST_TOKEN &&
                                   children[k]->token.type == TOKEN_WHITESPACE) {
                                k++;
                            }
                            if (k < i && children[k]->type == AST_TOKEN &&
                                children[k]->token.type == TOKEN_PUNCTUATION &&
                                token_text_equals(&children[k]->token, "(")) {
                                /* Exclude keywords */
                                if (strcmp(children[j]->token.text, "if") != 0 &&
                                    strcmp(children[j]->token.text, "while") != 0 &&
                                    strcmp(children[j]->token.text, "for") != 0 &&
                                    strcmp(children[j]->token.text, "switch") != 0) {
                                    function_name = children[j]->token.text;
                                }
                                break;
                            }
                        }
                    }
                }
            } else if (token_text_equals(tok, "}")) {
                brace_depth--;
                if (brace_depth == 0) {
                    function_name = NULL;
                }
            }
        }
    }

    return (brace_depth > 0) ? function_name : NULL;
}

/* Expand UNREACHABLE() calls inline */
void transpiler_expand_unreachable(ASTNode *ast, const char *filename) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT || !filename) {
        return;
    }

    /* Scan for UNREACHABLE(...) patterns */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        if (ast->children[i]->token.type != TOKEN_IDENTIFIER) continue;

        Token *tok = &ast->children[i]->token;
        if (!token_text_equals(tok, "UNREACHABLE")) continue;

        /* Found UNREACHABLE, check for ( ... ) */
        size_t j = skip_whitespace(ast->children, ast->child_count, i + 1);
        if (j >= ast->child_count) continue;
        if (ast->children[j]->type != AST_TOKEN) continue;
        if (!token_text_equals(&ast->children[j]->token, "(")) continue;

        /* Find the message string argument */
        size_t k = skip_whitespace(ast->children, ast->child_count, j + 1);
        if (k >= ast->child_count) continue;
        if (ast->children[k]->type != AST_TOKEN) continue;
        if (ast->children[k]->token.type != TOKEN_STRING) continue;

        char *msg_content = extract_string_content(ast->children[k]->token.text);
        if (!msg_content) continue;

        /* Find closing ) */
        size_t closing_paren = skip_whitespace(ast->children, ast->child_count, k + 1);
        if (closing_paren >= ast->child_count) {
            free(msg_content);
            continue;
        }
        if (!token_text_equals(&ast->children[closing_paren]->token, ")")) {
            free(msg_content);
            continue;
        }

        /* Get location info from the original UNREACHABLE token */
        int line = tok->line;
        const char *func_name = find_function_name(ast->children, ast->child_count, i);
        if (!func_name) func_name = "<unknown>";

        /* Build the replacement code */
        char replacement_code[1024];
        snprintf(replacement_code, sizeof(replacement_code),
                 "{ fprintf(stderr, \"%s:%d: %s: Unreachable code reached: %s\\n\"); abort(); }",
                 filename, line, func_name, msg_content);

        free(msg_content);

        /* Replace tokens from i to closing_paren with the inline code */
        /* Create new token with the replacement */
        char *replacement_text = strdup(replacement_code);
        if (!replacement_text) continue;

        free(ast->children[i]->token.text);
        ast->children[i]->token.text = replacement_text;
        ast->children[i]->token.length = strlen(replacement_text);
        ast->children[i]->token.type = TOKEN_PUNCTUATION; /* Treat as code block */

        /* Remove tokens from i+1 to closing_paren (inclusive) */
        size_t tokens_to_remove = closing_paren - i;
        for (size_t m = i + 1; m <= closing_paren && m < ast->child_count; m++) {
            if (ast->children[m]->token.text) {
                free(ast->children[m]->token.text);
            }
            free(ast->children[m]);
        }

        /* Shift remaining tokens */
        for (size_t m = i + 1; m + tokens_to_remove < ast->child_count; m++) {
            ast->children[m] = ast->children[m + tokens_to_remove];
        }
        ast->child_count -= tokens_to_remove;
    }
}
