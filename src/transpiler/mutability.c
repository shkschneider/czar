/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Transforms mutability keywords for C compilation.
 * Strategy: Transform 'mut' parameters to pointers for pass-by-reference semantics.
 */

#define _POSIX_C_SOURCE 200809L

#include "mutability.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Context for tracking mut parameters */
typedef struct {
    char **param_names;  /* Names of mut parameters */
    size_t count;
    size_t capacity;
} MutParamContext;

static MutParamContext g_mut_params = {NULL, 0, 0};

/* Add a mut parameter to the context */
static void add_mut_param(const char *name) {
    if (!name) return;
    
    if (g_mut_params.count >= g_mut_params.capacity) {
        size_t new_capacity = g_mut_params.capacity == 0 ? 8 : g_mut_params.capacity * 2;
        char **new_names = realloc(g_mut_params.param_names, new_capacity * sizeof(char*));
        if (!new_names) {
            fprintf(stderr, "[CZAR] Warning: Failed to expand mut param tracking\n");
            return;
        }
        g_mut_params.param_names = new_names;
        g_mut_params.capacity = new_capacity;
    }
    char *name_copy = strdup(name);
    if (!name_copy) {
        fprintf(stderr, "[CZAR] Warning: Failed to allocate memory for mut param name\n");
        return;
    }
    g_mut_params.param_names[g_mut_params.count++] = name_copy;
}

/* Check if a name is a mut parameter */
static int is_mut_param(const char *name) {
    for (size_t i = 0; i < g_mut_params.count; i++) {
        if (strcmp(g_mut_params.param_names[i], name) == 0) {
            return 1;
        }
    }
    return 0;
}

/* Clear mut parameter context */
static void clear_mut_params(void) {
    for (size_t i = 0; i < g_mut_params.count; i++) {
        free(g_mut_params.param_names[i]);
    }
    free(g_mut_params.param_names);
    g_mut_params.param_names = NULL;
    g_mut_params.count = 0;
    g_mut_params.capacity = 0;
}

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
static int is_in_function_params(ASTNode **children, size_t mut_idx) {
    /* Look backward for opening ( */
    int paren_count = 0;
    for (int i = (int)mut_idx - 1; i >= 0 && i >= (int)mut_idx - 30; i--) {
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
                    /* Found opening paren, now check if it's a function declaration */
                    /* Look backward for function name (identifier before the paren) */
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

/* Transform mut parameter: mut Type name -> Type* name */
static void transform_mut_parameter(ASTNode **children, size_t count, size_t mut_idx) {
    /* Skip mut and whitespace */
    size_t type_idx = skip_ws(children, count, mut_idx + 1);
    if (type_idx >= count || children[type_idx]->type != AST_TOKEN) return;
    
    /* Skip type and whitespace to find parameter name */
    size_t name_idx = skip_ws(children, count, type_idx + 1);
    if (name_idx >= count || children[name_idx]->type != AST_TOKEN) return;
    if (children[name_idx]->token.type != TOKEN_IDENTIFIER) return;
    
    /* Record the parameter name as mut */
    add_mut_param(children[name_idx]->token.text);
    
    /* Remove 'mut' keyword */
    Token *mut_token = &children[mut_idx]->token;
    char *empty_mut = strdup("");
    if (empty_mut) {
        free(mut_token->text);
        mut_token->text = empty_mut;
        mut_token->length = 0;
    }
    
    /* Remove whitespace after mut */
    if (mut_idx + 1 < count &&
        children[mut_idx + 1]->type == AST_TOKEN &&
        children[mut_idx + 1]->token.type == TOKEN_WHITESPACE) {
        Token *ws_token = &children[mut_idx + 1]->token;
        char *empty_ws = strdup("");
        if (empty_ws) {
            free(ws_token->text);
            ws_token->text = empty_ws;
            ws_token->length = 0;
        }
    }
    
    /* Add pointer (*) after the type */
    /* We need to insert a * token. For simplicity, prepend it to the parameter name */
    Token *name_token = &children[name_idx]->token;
    char *new_name = malloc(strlen(name_token->text) + 2);
    if (!new_name) {
        fprintf(stderr, "[CZAR] Warning: Failed to allocate memory for pointer parameter name\n");
        return;
    }
    sprintf(new_name, "*%s", name_token->text);
    free(name_token->text);
    name_token->text = new_name;
    name_token->length = strlen(new_name);
}

/* Transform operations on mut parameters: x + 1 -> *x + 1, x = ... -> *x = ... */
static void transform_mut_param_operations(ASTNode **children, size_t count, size_t i) {
    /* Check if this is a mut param identifier */
    if (children[i]->type != AST_TOKEN) return;
    if (children[i]->token.type != TOKEN_IDENTIFIER) return;
    if (!is_mut_param(children[i]->token.text)) return;
    
    /* Check what follows this identifier */
    size_t next_idx = skip_ws(children, count, i + 1);
    if (next_idx >= count || children[next_idx]->type != AST_TOKEN) return;
    
    const char *next_text = children[next_idx]->token.text;
    
    /* If followed by . or ->, skip (already handled by transform_member_access) */
    if (strcmp(next_text, ".") == 0 || strcmp(next_text, "->") == 0) {
        return;
    }
    
    /* If followed by [, it's array access - needs dereference */
    /* If followed by =, <, >, +, -, *, /, etc. - needs dereference */
    /* Basically, any use except member access needs dereference */
    
    /* Prepend * to the identifier */
    Token *id_token = &children[i]->token;
    char *new_text = malloc(strlen(id_token->text) + 2);
    if (!new_text) {
        fprintf(stderr, "[CZAR] Warning: Failed to allocate memory for dereference\n");
        return;
    }
    sprintf(new_text, "*%s", id_token->text);
    free(id_token->text);
    id_token->text = new_text;
    id_token->length = strlen(new_text);
}
static void transform_member_access(ASTNode **children, size_t count, size_t i) {
    /* Check if this is param_name */
    if (children[i]->type != AST_TOKEN) return;
    if (children[i]->token.type != TOKEN_IDENTIFIER) return;
    if (!is_mut_param(children[i]->token.text)) return;
    
    /* Look for . following this identifier */
    size_t dot_idx = skip_ws(children, count, i + 1);
    if (dot_idx >= count || children[dot_idx]->type != AST_TOKEN) return;
    if (strcmp(children[dot_idx]->token.text, ".") != 0) return;
    
    /* Transform . to -> */
    Token *dot_token = &children[dot_idx]->token;
    free(dot_token->text);
    dot_token->text = strdup("->");
    dot_token->length = 2;
}

/* Validate mutability rules - minimal validation */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source) {
    /* For now, just do minimal validation */
    (void)ast;
    (void)filename;
    (void)source;
}

/* Transform mutability keywords */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) {
        return;
    }

    if (ast->type == AST_TRANSLATION_UNIT) {
        /* Process functions one at a time to maintain proper scoping */
        size_t func_start = 0;
        
        while (func_start < ast->child_count) {
            /* Find next function definition */
            int in_function = 0;
            size_t func_end = func_start;
            
            for (size_t i = func_start; i < ast->child_count; i++) {
                if (ast->children[i]->type == AST_TOKEN) {
                    const char *text = ast->children[i]->token.text;
                    
                    if (strcmp(text, "{") == 0 && !in_function) {
                        /* Start of function body */
                        in_function = 1;
                    } else if (strcmp(text, "}") == 0 && in_function) {
                        /* End of function body */
                        func_end = i;
                        break;
                    } else if (strcmp(text, ";") == 0 && !in_function) {
                        /* Function declaration (not definition) */
                        func_end = i;
                        break;
                    }
                }
            }
            
            if (func_end <= func_start) {
                func_end = ast->child_count - 1;
            }
            
            /* Clear mut params for this function */
            clear_mut_params();
            
            /* First pass: Find and transform mut parameters in this function */
            for (size_t i = func_start; i <= func_end && i < ast->child_count; i++) {
                if (ast->children[i]->type == AST_TOKEN) {
                    Token *token = &ast->children[i]->token;
                    
                    /* Look for 'mut' keyword */
                    if (token->type == TOKEN_IDENTIFIER &&
                        strcmp(token->text, "mut") == 0) {
                        
                        /* Check if this is in a function parameter context */
                        if (is_in_function_params(ast->children, i)) {
                            /* Transform mut parameter to pointer */
                            transform_mut_parameter(ast->children, ast->child_count, i);
                        } else {
                            /* Just remove 'mut' keyword for local variables */
                            char *empty_local = strdup("");
                            if (empty_local) {
                                free(token->text);
                                token->text = empty_local;
                                token->length = 0;
                            }
                            
                            /* Also remove following whitespace */
                            if (i + 1 < ast->child_count &&
                                ast->children[i + 1]->type == AST_TOKEN &&
                                ast->children[i + 1]->token.type == TOKEN_WHITESPACE) {
                                Token *ws_token = &ast->children[i + 1]->token;
                                char *empty_local_ws = strdup("");
                                if (empty_local_ws) {
                                    free(ws_token->text);
                                    ws_token->text = empty_local_ws;
                                    ws_token->length = 0;
                                }
                            }
                        }
                    }
                }
            }
            
            /* Second pass: Transform member access on mut parameters in this function */
            for (size_t i = func_start; i <= func_end && i < ast->child_count; i++) {
                transform_member_access(ast->children, ast->child_count, i);
            }
            
            /* Third pass: Transform other operations on mut parameters in this function */
            for (size_t i = func_start; i <= func_end && i < ast->child_count; i++) {
                transform_mut_param_operations(ast->children, ast->child_count, i);
            }
            
            /* Move to next function */
            func_start = func_end + 1;
        }
    }

    /* Recursively transform children */
    for (size_t i = 0; i < ast->child_count; i++) {
        transpiler_transform_mutability(ast->children[i]);
    }
    
    /* Clear context when done with translation unit */
    if (ast->type == AST_TRANSLATION_UNIT) {
        clear_mut_params();
    }
}
