/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Transforms if-expressions to ternary operators according to CZar rules:
 * - if (condition) value1 else value2 -> (condition) ? value1 : value2
 * - Can be used in return statements: return if (cond) val1 else val2;
 * - Can be used in variable declarations: u8 i = if (cond) val1 else val2;
 */

#include "cz.h"
#include "ifexpr.h"
#include "../transpiler.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Helper: Check if token text matches */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) {
        return 0;
    }
    return strcmp(token->text, text) == 0;
}

/* Helper: Skip whitespace and comment tokens */
static size_t skip_whitespace(ASTNode_t **children, size_t count, size_t start) {
    while (start < count && children[start]->type == AST_TOKEN) {
        Token *t = &children[start]->token;
        if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) {
            start++;
        } else {
            break;
        }
    }
    return start;
}

/* Transform if-expressions to ternary operators */
void transpiler_transform_ifexpr(ASTNode_t *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode_t **children = ast->children;
    size_t count = ast->child_count;

    /* Look for pattern: if ( condition ) value else value2 */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Look for 'if' keyword that's not followed by a statement block */
        if ((token->type == TOKEN_IDENTIFIER || token->type == TOKEN_KEYWORD) && 
            token_text_equals(token, "if")) {
            
            /* Skip whitespace */
            size_t j = skip_whitespace(children, count, i + 1);

            /* Expect '(' */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_PUNCTUATION ||
                !token_text_equals(&children[j]->token, "(")) {
                continue;
            }

            /* Find matching ')' for the condition */
            int paren_depth = 1;
            j = skip_whitespace(children, count, j + 1);
            
            while (j < count && paren_depth > 0) {
                if (children[j]->type == AST_TOKEN) {
                    Token *t = &children[j]->token;
                    if (t->type == TOKEN_PUNCTUATION) {
                        if (token_text_equals(t, "(")) {
                            paren_depth++;
                        } else if (token_text_equals(t, ")")) {
                            paren_depth--;
                            if (paren_depth == 0) {
                                break;
                            }
                        }
                    }
                }
                j++;
            }

            if (j >= count) {
                continue; /* Couldn't find closing paren */
            }
            size_t close_paren = j;

            /* Skip whitespace after ')' */
            j = skip_whitespace(children, count, j + 1);

            /* Check if this is followed by '{' - if so, it's a regular if statement, not an if-expression */
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_PUNCTUATION &&
                token_text_equals(&children[j]->token, "{")) {
                continue; /* This is a regular if statement */
            }

            /* Now we need to find the 'else' keyword to confirm this is an if-expression */
            /* First, collect tokens until we find 'else' or ';' or '{' */
            size_t true_value_start = j;
            size_t else_pos = 0;
            int depth = 0;

            while (j < count) {
                if (children[j]->type == AST_TOKEN) {
                    Token *t = &children[j]->token;
                    
                    /* Track depth for nested expressions */
                    if (t->type == TOKEN_PUNCTUATION) {
                        if (token_text_equals(t, "(") || token_text_equals(t, "{") || token_text_equals(t, "[")) {
                            depth++;
                        } else if (token_text_equals(t, ")") || token_text_equals(t, "}") || token_text_equals(t, "]")) {
                            depth--;
                        } else if (token_text_equals(t, ";") && depth == 0) {
                            /* End of statement without else - not an if-expression */
                            break;
                        }
                    }
                    
                    /* Look for 'else' keyword at depth 0 */
                    if (depth == 0 && (t->type == TOKEN_IDENTIFIER || t->type == TOKEN_KEYWORD) && 
                        token_text_equals(t, "else")) {
                        else_pos = j;
                        break;
                    }
                }
                j++;
            }

            if (else_pos == 0) {
                continue; /* No 'else' found - this is a regular if statement */
            }

            size_t true_value_end = else_pos;

            /* Skip whitespace after 'else' */
            j = skip_whitespace(children, count, else_pos + 1);

            /* Check if 'else' is followed by '{' - if so, it's a regular if statement */
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_PUNCTUATION &&
                token_text_equals(&children[j]->token, "{")) {
                continue; /* This is a regular if statement */
            }

            /* Collect false value tokens until ';' or ',' or ')' or end */
            depth = 0;

            while (j < count) {
                if (children[j]->type == AST_TOKEN) {
                    Token *t = &children[j]->token;
                    
                    if (t->type == TOKEN_PUNCTUATION) {
                        if (token_text_equals(t, "(") || token_text_equals(t, "{") || token_text_equals(t, "[")) {
                            depth++;
                        } else if (token_text_equals(t, ")") || token_text_equals(t, "}") || token_text_equals(t, "]")) {
                            if (depth == 0) {
                                /* End of false value */
                                break;
                            }
                            depth--;
                        } else if ((token_text_equals(t, ";") || token_text_equals(t, ",")) && depth == 0) {
                            /* End of false value */
                            break;
                        }
                    }
                }
                j++;
            }

            /* Now we have all the pieces, transform the if-expression to ternary */
            /* Pattern: if ( condition ) true_value else false_value
             * Becomes: ( condition ) ? true_value : false_value
             */

            /* Remove 'if' keyword by setting it to empty */
            free(children[i]->token.text);
            children[i]->token.text = strdup("");
            children[i]->token.length = 0;

            /* '(' stays as '(' */
            /* condition tokens stay as-is */
            /* ')' at close_paren stays as ')' */

            /* Insert '?' after the condition */
            /* Find first non-whitespace token in true_value */
            size_t first_true_token = skip_whitespace(children, count, true_value_start);
            
            if (first_true_token < true_value_end && first_true_token > close_paren) {
                /* Prepend '?' to the first true value token */
                Token *first_t = &children[first_true_token]->token;
                char *new_text = malloc(first_t->length + 4); /* +4 for " ? " + null */
                if (new_text) {
                    snprintf(new_text, first_t->length + 4, " ? %s", first_t->text);
                    free(first_t->text);
                    first_t->text = new_text;
                    first_t->length = strlen(new_text);
                }
            }

            /* Replace 'else' with ' : ' */
            free(children[else_pos]->token.text);
            children[else_pos]->token.text = strdup(" : ");
            children[else_pos]->token.length = 3;
            children[else_pos]->token.type = TOKEN_OPERATOR;
        }
    }
}
