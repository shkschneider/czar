/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Transforms mutability keywords for C compilation.
 * Strategy: mut = opposite of const. Strip mut, add const for non-mut.
 * Let the C compiler do the heavy checking.
 */

#define _POSIX_C_SOURCE 200809L

#include "mutability.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Skip whitespace/comment tokens */
static size_t skip_ws(ASTNode **children, size_t count, size_t i) {
    while (i < count && children[i]->type == AST_TOKEN &&
           (children[i]->token.type == TOKEN_WHITESPACE ||
            children[i]->token.type == TOKEN_COMMENT)) {
        i++;
    }
    return i;
}

/* Check if we're in a function parameter list context */
static int is_in_function_params(ASTNode **children, size_t idx) {
    /* Look backward for opening ( */
    int paren_count = 0;
    for (int i = (int)idx - 1; i >= 0 && i >= (int)idx - 30; i--) {
        if (children[i]->type == AST_TOKEN) {
            const char *text = children[i]->token.text;
            
            /* Check for statement/block terminators - we're not in function params */
            if (strcmp(text, ";") == 0 || strcmp(text, "{") == 0 || strcmp(text, "}") == 0) {
                return 0;
            }
            
            /* Check for for/while/if keywords - not function params */
            if (children[i]->token.type == TOKEN_KEYWORD &&
                (strcmp(text, "for") == 0 || strcmp(text, "while") == 0 || 
                 strcmp(text, "if") == 0 || strcmp(text, "switch") == 0)) {
                return 0;
            }
            
            /* Track parentheses */
            if (strcmp(text, ")") == 0) {
                paren_count++;
            } else if (strcmp(text, "(") == 0) {
                paren_count--;
                if (paren_count < 0) {
                    /* Found opening paren, check if it's a function declaration */
                    for (int j = i - 1; j >= 0 && j >= i - 10; j--) {
                        if (children[j]->type == AST_TOKEN) {
                            if (children[j]->token.type == TOKEN_WHITESPACE || 
                                children[j]->token.type == TOKEN_COMMENT) {
                                continue;
                            }
                            /* Should be an identifier (function name) */
                            if (children[j]->token.type == TOKEN_IDENTIFIER) {
                                /* Check if before the identifier is a return type */
                                for (int k = j - 1; k >= 0 && k >= j - 10; k--) {
                                    if (children[k]->type == AST_TOKEN) {
                                        if (children[k]->token.type == TOKEN_WHITESPACE ||
                                            children[k]->token.type == TOKEN_COMMENT) {
                                            continue;
                                        }
                                        /* Check if it's a type keyword */
                                        const char *type_text = children[k]->token.text;
                                        if (children[k]->token.type == TOKEN_KEYWORD ||
                                            children[k]->token.type == TOKEN_IDENTIFIER) {
                                            /* Common type keywords */
                                            if (strcmp(type_text, "void") == 0 ||
                                                strcmp(type_text, "int") == 0 ||
                                                strcmp(type_text, "char") == 0 ||
                                                strcmp(type_text, "float") == 0 ||
                                                strcmp(type_text, "double") == 0 ||
                                                strncmp(type_text, "u", 1) == 0 ||  /* u8, u16, u32, u64 */
                                                strncmp(type_text, "i", 1) == 0) {  /* i8, i16, i32, i64 */
                                                return 1;  /* This is a function parameter */
                                            }
                                        }
                                        break;
                                    }
                                }
                            }
                            break;
                        }
                    }
                    return 0;
                }
            }
        }
    }
    return 0;
}

/* Check if next non-whitespace token is a pointer (*) */
static int is_followed_by_pointer(ASTNode **children, size_t count, size_t type_idx) {
    size_t next_idx = skip_ws(children, count, type_idx + 1);
    if (next_idx >= count || children[next_idx]->type != AST_TOKEN) return 0;
    return strcmp(children[next_idx]->token.text, "*") == 0;
}

/* Validate mutability rules - mut parameters must be pointers */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) return;
    
    /* Look for 'mut' keywords in function parameters */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type == AST_TOKEN) {
            Token *token = &ast->children[i]->token;
            
            /* Look for 'mut' keyword in function parameter context */
            if (token->type == TOKEN_IDENTIFIER &&
                strcmp(token->text, "mut") == 0 &&
                is_in_function_params(ast->children, i)) {
                
                /* Check if followed by a type */
                size_t type_idx = skip_ws(ast->children, ast->child_count, i + 1);
                if (type_idx >= ast->child_count || ast->children[type_idx]->type != AST_TOKEN) continue;
                
                /* Check if the type is followed by a pointer (*) */
                if (!is_followed_by_pointer(ast->children, ast->child_count, type_idx)) {
                    /* mut parameter is not a pointer - ERROR */
                    char error_msg[256];
                    snprintf(error_msg, sizeof(error_msg),
                            "mut parameters must be pointers. Use 'mut Type* param' not 'mut Type param'");
                    cz_error(filename, source, token->line, error_msg);
                }
            }
        }
    }
}

/* Transform mutability keywords */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) return;

    if (ast->type == AST_TRANSLATION_UNIT) {
        /* Simple transformation: Strip 'mut' keyword */
        /* Adding 'const' for non-mut parameters is complex and requires
         * full parameter boundary detection. For now, we let developers
         * understand intent through mut keyword presence/absence.
         */
        
        for (size_t i = 0; i < ast->child_count; i++) {
            if (ast->children[i]->type == AST_TOKEN) {
                Token *token = &ast->children[i]->token;
                
                /* Look for 'mut' keyword */
                if (token->type == TOKEN_IDENTIFIER &&
                    strcmp(token->text, "mut") == 0) {
                    
                    /* Remove 'mut' keyword */
                    free(token->text);
                    token->text = strdup("");
                    if (!token->text) {
                        fprintf(stderr, "[CZAR] Warning: Failed to allocate memory\n");
                        token->text = "";
                    }
                    token->length = 0;
                    
                    /* Also remove following whitespace */
                    if (i + 1 < ast->child_count &&
                        ast->children[i + 1]->type == AST_TOKEN &&
                        ast->children[i + 1]->token.type == TOKEN_WHITESPACE) {
                        Token *ws_token = &ast->children[i + 1]->token;
                        free(ws_token->text);
                        ws_token->text = strdup("");
                        if (!ws_token->text) {
                            fprintf(stderr, "[CZAR] Warning: Failed to allocate memory\n");
                            ws_token->text = "";
                        }
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
