/*
 * CZar - C semantic authority layer
 * Transpiler defer module (transpiler/defer.c)
 *
 * Handles defer keyword for scope-exit cleanup using cleanup attribute.
 * Transforms: defer free(p)
 * Into: void _cz_defer_cleanup_N(void **arg) { free(*arg); }
 *       void *_cz_defer_N __attribute__((cleanup(_cz_defer_cleanup_N))) = p;
 */

#include "cz.h"
#include "defer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Counter for generating unique defer variable names */
static int defer_counter = 0;

/* Helper to duplicate a string with length limit */
static char* safe_strndup(const char *str, size_t len) {
    if (!str) return NULL;
    char *result = malloc(len + 1);
    if (!result) return NULL;
    memcpy(result, str, len);
    result[len] = '\0';
    return result;
}

/* Helper to check if token text matches a string */
static int token_matches(Token *tok, const char *str) {
    if (!tok || !tok->text || !str) return 0;
    size_t len = strlen(str);
    return tok->length == len && strncmp(tok->text, str, len) == 0;
}

/* Helper to skip whitespace and comments */
static size_t skip_whitespace(ASTNode **children, size_t count, size_t start) {
    if (!children) return count;
    for (size_t i = start; i < count; i++) {
        if (!children[i] || children[i]->type != AST_TOKEN) continue;
        TokenType type = children[i]->token.type;
        if (type != TOKEN_WHITESPACE && type != TOKEN_COMMENT) {
            return i;
        }
    }
    return count;
}

/* Helper to extract function name from defer statement */
/* Returns newly allocated string or NULL on failure */
static char* extract_function_name(ASTNode **children, size_t count, size_t start, size_t *end_pos) {
    if (!children) return NULL;
    size_t i = start;
    char *func_name = NULL;
    
    /* Find the function identifier */
    while (i < count) {
        if (!children[i] || children[i]->type != AST_TOKEN) {
            i++;
            continue;
        }
        
        Token *tok = &children[i]->token;
        
        if (tok->type == TOKEN_WHITESPACE || tok->type == TOKEN_COMMENT) {
            i++;
            continue;
        }
        
        if (tok->type == TOKEN_IDENTIFIER) {
            func_name = safe_strndup(tok->text, tok->length);
            i++;
            break;
        }
        
        /* If we hit something that's not whitespace/comment/identifier, bail */
        break;
    }
    
    if (end_pos) *end_pos = i;
    return func_name;
}

/* Helper to extract argument from defer statement */
/* Returns newly allocated string or NULL on failure */
static char* extract_argument(ASTNode **children, size_t count, size_t start, size_t *end_pos) {
    if (!children) return NULL;
    size_t i = start;
    char *arg = NULL;
    
    /* Skip to opening parenthesis */
    i = skip_whitespace(children, count, i);
    if (i >= count || !children[i] || children[i]->type != AST_TOKEN) {
        return NULL;
    }
    
    if (!token_matches(&children[i]->token, "(")) {
        return NULL;
    }
    i++;
    
    /* Skip whitespace after ( */
    i = skip_whitespace(children, count, i);
    if (i >= count || !children[i] || children[i]->type != AST_TOKEN) {
        return NULL;
    }
    
    /* Get the argument identifier */
    Token *tok = &children[i]->token;
    if (tok->type == TOKEN_IDENTIFIER) {
        arg = safe_strndup(tok->text, tok->length);
        i++;
    } else {
        return NULL;
    }
    
    /* Skip to closing parenthesis */
    i = skip_whitespace(children, count, i);
    if (i >= count || !children[i] || children[i]->type != AST_TOKEN) {
        free(arg);
        return NULL;
    }
    
    if (token_matches(&children[i]->token, ")")) {
        i++;
    } else {
        free(arg);
        return NULL;
    }
    
    /* Skip to semicolon */
    i = skip_whitespace(children, count, i);
    if (i < count && children[i] && children[i]->type == AST_TOKEN && token_matches(&children[i]->token, ";")) {
        /* Don't increment i - we want end_pos to point to the semicolon, not after it */
        /* This way we preserve the semicolon in the output */
    }
    
    if (end_pos) *end_pos = i;
    return arg;
}

/* Helper to clear token text (emit function handles NULL text) */
static void clear_token_text(Token *token) {
    if (!token) return;
    free(token->text);
    token->text = NULL;
    token->length = 0;
}

/* Helper to set token text */
static int set_token_text(Token *token, const char *text) {
    if (!token || !text) return 0;
    char *new_text = strdup(text);
    if (!new_text) return 0;
    free(token->text);
    token->text = new_text;
    token->length = strlen(text);
    return 1;
}

/* Transform defer statements to cleanup attribute pattern */
void transpiler_transform_defer(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    if (!ast->children || ast->child_count == 0) {
        return;
    }
    
    /* Reset defer counter for each translation unit */
    defer_counter = 0;
    
    /* Scan for defer patterns */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (!ast->children[i]) continue;
        if (ast->children[i]->type != AST_TOKEN) continue;
        if (ast->children[i]->token.type != TOKEN_IDENTIFIER) continue;
        
        Token *tok = &ast->children[i]->token;
        
        /* Check if this is "defer" keyword */
        if (!token_matches(tok, "defer")) {
            continue;
        }
        
        
        /* Found defer keyword */
        size_t func_end_pos = 0;
        char *func_name = extract_function_name(ast->children, ast->child_count, i + 1, &func_end_pos);
        if (!func_name) {
            /* Invalid defer syntax, just clear the defer keyword */
            clear_token_text(tok);
            continue;
        }
        
        size_t arg_end_pos = 0;
        char *arg = extract_argument(ast->children, ast->child_count, func_end_pos, &arg_end_pos);
        if (!arg) {
            free(func_name);
            /* Invalid defer syntax, just clear the defer keyword */
            clear_token_text(tok);
            continue;
        }
        
        /* Generate the replacement code */
        /* Transform: defer cleanup_func(var); */
        /* Into: __attribute__((cleanup(cleanup_func))) void *_cz_defer_N = var; */
        /* User must provide cleanup_func with signature: void cleanup_func(void **ptr) */
        
        char buffer[512];
        int n = snprintf(buffer, sizeof(buffer),
            "__attribute__((cleanup(%s))) void *_cz_defer_%d = %s",
            func_name, defer_counter, arg);
        
        
        if (n < 0 || n >= (int)sizeof(buffer)) {
            /* Buffer overflow, skip this defer */
            free(func_name);
            free(arg);
            clear_token_text(tok);
            continue;
        }
        
        defer_counter++;
        
        /* Replace the defer keyword with the generated code */
        if (!set_token_text(tok, buffer)) {
            free(func_name);
            free(arg);
            clear_token_text(tok);
            continue;
        }
        
        /* Clear all tokens from defer keyword to semicolon by replacing with spaces */
        for (size_t j = i + 1; j < arg_end_pos && j < ast->child_count; j++) {
            if (ast->children[j] && ast->children[j]->type == AST_TOKEN) {
                /* Instead of clearing, replace with a space */
                Token *t = &ast->children[j]->token;
                if (t->text) {
                    free(t->text);
                    t->text = strdup(" ");
                    t->length = t->text ? 1 : 0;
                    t->type = TOKEN_WHITESPACE;
                }
            }
        }
        
        
        free(func_name);
        free(arg);
    }
}
