/*
 * CZar - C semantic authority layer
 * Transpiler functions module (transpiler/functions.c)
 *
 * Handles function-related transformations and validations.
 */

#define _POSIX_C_SOURCE 200809L

#include "functions.h"
#include "../warnings.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Global context for error/warning reporting */
static const char *g_filename = NULL;
static const char *g_source = NULL;

/* Helper function to check if token text matches */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) {
        return 0;
    }
    return strcmp(token->text, text) == 0;
}

/* Skip whitespace and comment tokens */
static size_t skip_whitespace(ASTNode **children, size_t count, size_t i) {
    while (i < count) {
        if (children[i]->type != AST_TOKEN) {
            i++;
            continue;
        }
        TokenType type = children[i]->token.type;
        if (type != TOKEN_WHITESPACE && type != TOKEN_COMMENT) {
            break;
        }
        i++;
    }
    return i;
}

/* Validate and transform function declarations */
void transpiler_validate_functions(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    g_filename = filename;
    g_source = source;

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    /* Scan for function declarations */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (children[i]->token.type != TOKEN_IDENTIFIER) continue;

        Token *tok = &children[i]->token;
        
        /* Look for function name followed by ( */
        size_t j = skip_whitespace(children, count, i + 1);
        if (j >= count) continue;
        if (children[j]->type != AST_TOKEN) continue;
        if (!token_text_equals(&children[j]->token, "(")) continue;

        /* This looks like a function call or declaration */
        /* Check if this is a function declaration by looking backward for return type */
        int is_function_decl = 0;
        for (int k = (int)i - 1; k >= 0 && k >= (int)i - 10; k--) {
            if (children[k]->type != AST_TOKEN) continue;
            if (children[k]->token.type == TOKEN_WHITESPACE || 
                children[k]->token.type == TOKEN_COMMENT) continue;
            
            /* Check if previous token is a type keyword or identifier */
            if (children[k]->token.type == TOKEN_KEYWORD || 
                children[k]->token.type == TOKEN_IDENTIFIER) {
                const char *text = children[k]->token.text;
                if (strcmp(text, "void") == 0 || strcmp(text, "int") == 0 ||
                    strcmp(text, "char") == 0 || strcmp(text, "short") == 0 ||
                    strcmp(text, "long") == 0 || strcmp(text, "float") == 0 ||
                    strcmp(text, "double") == 0 || strcmp(text, "unsigned") == 0 ||
                    strcmp(text, "signed") == 0 || strcmp(text, "u8") == 0 ||
                    strcmp(text, "u16") == 0 || strcmp(text, "u32") == 0 ||
                    strcmp(text, "u64") == 0 || strcmp(text, "i8") == 0 ||
                    strcmp(text, "i16") == 0 || strcmp(text, "i32") == 0 ||
                    strcmp(text, "i64") == 0 || strcmp(text, "uint8_t") == 0 ||
                    strcmp(text, "uint16_t") == 0 || strcmp(text, "uint32_t") == 0 ||
                    strcmp(text, "uint64_t") == 0 || strcmp(text, "int8_t") == 0 ||
                    strcmp(text, "int16_t") == 0 || strcmp(text, "int32_t") == 0 ||
                    strcmp(text, "int64_t") == 0 || strcmp(text, "bool") == 0 ||
                    strcmp(text, "size_t") == 0 || strcmp(text, "const") == 0 ||
                    strcmp(text, "static") == 0 || strcmp(text, "inline") == 0) {
                    is_function_decl = 1;
                    break;
                }
            }
            break; /* Stop at first non-whitespace token */
        }

        if (!is_function_decl) continue;

        /* Now check the parameter list */
        int paren_depth = 1;
        j++;
        int has_content = 0;

        while (j < count && paren_depth > 0) {
            if (children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_PUNCTUATION) {
                if (token_text_equals(&children[j]->token, "(")) {
                    paren_depth++;
                } else if (token_text_equals(&children[j]->token, ")")) {
                    paren_depth--;
                    if (paren_depth == 0) {
                        break;
                    }
                }
            }
            /* Check if there's any content between parens */
            if (children[j]->type == AST_TOKEN && 
                children[j]->token.type != TOKEN_WHITESPACE &&
                children[j]->token.type != TOKEN_COMMENT) {
                has_content = 1;
            }
            j++;
        }

        /* If empty parameter list (), warn user */
        if (!has_content) {
            char warning_msg[256];
            snprintf(warning_msg, sizeof(warning_msg),
                     "Function '%s' declared with empty parameter list (). "
                     "Prefer explicit 'void' parameter: %s(void)",
                     tok->text, tok->text);
            cz_warning(g_filename, g_source, tok->line, warning_msg);
        }
    }
}

/* Transform function declarations (main return type, empty parameter lists) */
void transpiler_transform_functions(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    /* Scan for function declarations */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (children[i]->token.type != TOKEN_IDENTIFIER) continue;

        Token *tok = &children[i]->token;
        
        /* Check if this is 'main' function */
        int is_main = (strcmp(tok->text, "main") == 0);
        
        /* Look for function name followed by ( */
        size_t j = skip_whitespace(children, count, i + 1);
        if (j >= count) continue;
        if (children[j]->type != AST_TOKEN) continue;
        if (!token_text_equals(&children[j]->token, "(")) continue;

        /* This looks like a function */
        /* Check if this is a function declaration by looking backward for return type */
        int return_type_idx = -1;
        for (int k = (int)i - 1; k >= 0 && k >= (int)i - 10; k--) {
            if (children[k]->type != AST_TOKEN) continue;
            if (children[k]->token.type == TOKEN_WHITESPACE || 
                children[k]->token.type == TOKEN_COMMENT) continue;
            
            /* Check if previous token is a type */
            if (children[k]->token.type == TOKEN_KEYWORD || 
                children[k]->token.type == TOKEN_IDENTIFIER) {
                return_type_idx = k;
                break;
            }
            break;
        }

        if (return_type_idx < 0) continue;

        /* Transform main() return type to int if it's u32 or other type */
        if (is_main) {
            Token *return_type = &children[return_type_idx]->token;
            if (strcmp(return_type->text, "u32") != 0 && 
                strcmp(return_type->text, "int") != 0) {
                /* Already int or something else, skip */
            } else if (strcmp(return_type->text, "u32") == 0 ||
                       strcmp(return_type->text, "uint32_t") == 0) {
                /* Replace with int */
                free(return_type->text);
                return_type->text = strdup("int");
                return_type->length = 3;
            }
        }

        /* Now handle empty parameter list transformation */
        int paren_depth = 1;
        j++;
        size_t first_content_idx = j;
        int has_content = 0;

        while (j < count && paren_depth > 0) {
            if (children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_PUNCTUATION) {
                if (token_text_equals(&children[j]->token, "(")) {
                    paren_depth++;
                } else if (token_text_equals(&children[j]->token, ")")) {
                    paren_depth--;
                    if (paren_depth == 0) {
                        /* If empty parameter list, insert 'void' */
                        if (!has_content) {
                            /* Create new nodes for 'void' */
                            ASTNode *void_node = malloc(sizeof(ASTNode));
                            if (void_node) {
                                void_node->type = AST_TOKEN;
                                void_node->token.type = TOKEN_KEYWORD;
                                void_node->token.text = strdup("void");
                                void_node->token.length = 4;
                                void_node->token.line = tok->line;
                                void_node->token.column = tok->column;
                                void_node->children = NULL;
                                void_node->child_count = 0;
                                void_node->child_capacity = 0;

                                /* Insert void node after opening paren */
                                /* Grow array if needed */
                                if (ast->child_count >= ast->child_capacity) {
                                    size_t new_capacity = ast->child_capacity == 0 ? 8 : ast->child_capacity * 2;
                                    ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
                                    if (new_children) {
                                        ast->children = new_children;
                                        ast->child_capacity = new_capacity;
                                        children = ast->children; /* Update local pointer */
                                    }
                                }

                                /* Shift elements to make room */
                                if (ast->child_count < ast->child_capacity) {
                                    for (size_t m = ast->child_count; m > first_content_idx; m--) {
                                        ast->children[m] = ast->children[m - 1];
                                    }
                                    ast->children[first_content_idx] = void_node;
                                    ast->child_count++;
                                    count = ast->child_count; /* Update local count */
                                }
                            }
                        }
                        break;
                    }
                }
            }
            /* Check if there's any content between parens */
            if (children[j]->type == AST_TOKEN && 
                children[j]->token.type != TOKEN_WHITESPACE &&
                children[j]->token.type != TOKEN_COMMENT) {
                has_content = 1;
            }
            j++;
        }
    }
}
