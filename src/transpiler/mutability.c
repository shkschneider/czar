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

/* Check if we're looking at the start of a parameter (after opening paren or comma) */
static int is_param_start(ASTNode **children, size_t idx) {
    /* Look backward for ( or , */
    for (int i = (int)idx - 1; i >= 0 && i >= (int)idx - 10; i--) {
        if (children[i]->type == AST_TOKEN) {
            if (children[i]->token.type == TOKEN_WHITESPACE ||
                children[i]->token.type == TOKEN_COMMENT) {
                continue;
            }
            const char *text = children[i]->token.text;
            if (strcmp(text, "(") == 0 || strcmp(text, ",") == 0) {
                return 1;
            }
            /* If we find something else first, it's not param start */
            return 0;
        }
    }
    return 0;
}

/* Helper function to create a new token node */
static ASTNode *create_token_node(TokenType type, const char *text, int line) {
    ASTNode *node = malloc(sizeof(ASTNode));
    if (!node) return NULL;
    
    node->type = AST_TOKEN;
    node->token.type = type;
    node->token.text = strdup(text);
    if (!node->token.text) {
        free(node);
        return NULL;
    }
    node->token.length = strlen(text);
    node->token.line = line;
    node->token.column = 0;
    node->children = NULL;
    node->child_count = 0;
    node->child_capacity = 0;
    
    return node;
}

/* Insert a node into the AST at the specified position */
static int insert_node_at(ASTNode *ast, size_t position, ASTNode *node) {
    /* Ensure capacity */
    if (ast->child_count + 1 > ast->child_capacity) {
        size_t new_capacity = (ast->child_capacity == 0) ? 16 : ast->child_capacity * 2;
        ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
        if (!new_children) {
            return 0; /* Allocation failed */
        }
        ast->children = new_children;
        ast->child_capacity = new_capacity;
    }
    
    /* Shift elements to make room */
    for (size_t i = ast->child_count; i > position; i--) {
        ast->children[i] = ast->children[i - 1];
    }
    
    /* Insert the node */
    ast->children[position] = node;
    ast->child_count++;
    
    return 1;
}

/* Transform mutability keywords */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) return;

    if (ast->type == AST_TRANSLATION_UNIT) {
        /* Two transformations:
         * 1. Strip 'mut' keyword (making it mutable in C)
         * 2. Add 'const' for parameters without 'mut' (making them immutable in C)
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
                        fprintf(stderr, "[CZAR] Warning: Failed to allocate memory for empty string\n");
                        token->text = malloc(1);
                        if (token->text) {
                            token->text[0] = '\0';
                        }
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
                            fprintf(stderr, "[CZAR] Warning: Failed to allocate memory for empty string\n");
                            ws_token->text = malloc(1);
                            if (ws_token->text) {
                                ws_token->text[0] = '\0';
                            }
                        }
                        ws_token->length = 0;
                    }
                }
                /* Look for type keywords in function parameter context (without preceding 'mut') */
                else if (is_in_function_params(ast->children, i) &&
                         is_param_start(ast->children, i) &&
                         (token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER)) {
                    
                    /* Check if this looks like a type (common types or identifiers that could be typedefs) */
                    /* EXCLUDE void - it cannot be qualified with const */
                    const char *text = token->text;
                    int is_type = (strcmp(text, "int") == 0 ||
                                  strcmp(text, "char") == 0 ||
                                  strcmp(text, "float") == 0 ||
                                  strcmp(text, "double") == 0 ||
                                  strncmp(text, "u", 1) == 0 ||  /* u8, u16, u32, u64 */
                                  strncmp(text, "i", 1) == 0 ||  /* i8, i16, i32, i64 */
                                  strcmp(text, "bool") == 0 ||
                                  strcmp(text, "size_t") == 0 ||
                                  /* Also check for common identifier patterns (struct typedefs) */
                                  (token->type == TOKEN_IDENTIFIER && isupper(text[0])));
                    
                    if (is_type) {
                        /* Check if NOT preceded by 'mut' or 'const' (look back, skipping whitespace) */
                        int has_mut = 0;
                        int has_const = 0;
                        for (int j = (int)i - 1; j >= 0 && j >= (int)i - 5; j--) {
                            if (ast->children[j]->type == AST_TOKEN) {
                                if (ast->children[j]->token.type == TOKEN_WHITESPACE ||
                                    ast->children[j]->token.type == TOKEN_COMMENT) {
                                    continue;
                                }
                                if (ast->children[j]->token.type == TOKEN_IDENTIFIER &&
                                    strcmp(ast->children[j]->token.text, "mut") == 0) {
                                    has_mut = 1;
                                }
                                if (ast->children[j]->token.type == TOKEN_KEYWORD &&
                                    strcmp(ast->children[j]->token.text, "const") == 0) {
                                    has_const = 1;
                                }
                                break;
                            }
                        }
                        
                        /* If no 'mut' and no 'const', insert a 'const' token before the type */
                        if (!has_mut && !has_const) {
                            ASTNode *const_node = create_token_node(TOKEN_KEYWORD, "const", token->line);
                            ASTNode *space_node = create_token_node(TOKEN_WHITESPACE, " ", token->line);
                            
                            if (const_node && space_node) {
                                /* Insert const and space before the current position */
                                if (insert_node_at(ast, i, const_node) &&
                                    insert_node_at(ast, i + 1, space_node)) {
                                    /* Adjust loop counter since we inserted 2 nodes */
                                    i += 2;
                                } else {
                                    /* Failed to insert, clean up */
                                    if (const_node) {
                                        if (const_node->token.text) free(const_node->token.text);
                                        free(const_node);
                                    }
                                    if (space_node) {
                                        if (space_node->token.text) free(space_node->token.text);
                                        free(space_node);
                                    }
                                }
                            } else {
                                /* Failed to create nodes, clean up */
                                if (const_node) {
                                    if (const_node->token.text) free(const_node->token.text);
                                    free(const_node);
                                }
                                if (space_node) {
                                    if (space_node->token.text) free(space_node->token.text);
                                    free(space_node);
                                }
                            }
                        }
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
