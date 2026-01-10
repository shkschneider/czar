/*
 * CZar - C semantic authority layer
 * Transpiler defer module (transpiler/defer.c)
 *
 * Handles #defer keyword for scope-exit cleanup using cleanup attribute.
 * Transforms: type var = init() #defer cleanup_func;
 * Into: __attribute__((cleanup(cleanup_func))) type var = init();
 */

#include "cz.h"
#include "defer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

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

/* Transform #defer declarations to cleanup attribute pattern */
void transpiler_transform_defer(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    if (!ast->children || ast->child_count == 0) {
        return;
    }
    
    
    /* Scan for #defer patterns in declarations */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (!ast->children[i]) continue;
        if (ast->children[i]->type != AST_TOKEN) continue;
        
        Token *tok = &ast->children[i]->token;
        
        /* Look for #defer preprocessor directive */
        if (tok->type != TOKEN_PREPROCESSOR) continue;
        if (!tok->text) continue;
        
        
        /* Check for #defer - handle both "#defer" and "#defer " */
        size_t defer_len = strlen("#defer");
        if (tok->length < defer_len) continue;
        if (strncmp(tok->text, "#defer", defer_len) != 0) continue;
        
        
        /* Check it's exactly #defer, not #defer_something */
        if (tok->length > defer_len) {
            char next_char = tok->text[defer_len];
            if (next_char != ' ' && next_char != '\t' && next_char != '\r' && next_char != '\n') {
                continue;
            }
        }
        
        /* Extract cleanup function name from the #defer directive */
        /* The token text is "#defer cleanup_func;" or "#defer cleanup_func" */
        const char *func_start = tok->text + defer_len;
        while (*func_start && (*func_start == ' ' || *func_start == '\t')) {
            func_start++;
        }
        
        if (!*func_start || *func_start == ';' || *func_start == '\n') {
            /* No function name found */
            continue;
        }
        
        /* Find the end of the function name */
        const char *func_end = func_start;
        while (*func_end && *func_end != ' ' && *func_end != '\t' && *func_end != ';' && *func_end != '\n') {
            func_end++;
        }
        
        size_t func_len = func_end - func_start;
        if (func_len == 0) continue;
        
        char *cleanup_func = malloc(func_len + 1);
        if (!cleanup_func) continue;
        memcpy(cleanup_func, func_start, func_len);
        cleanup_func[func_len] = '\0';
        
        
        /* Find the type token by scanning backwards from #defer */
        /* We need to find the first token of the declaration */
        size_t type_pos = 0;
        int found = 0;
        
        
        for (size_t j = i; j > 0; j--) {
            size_t idx = j - 1;
            if (!ast->children[idx] || ast->children[idx]->type != AST_TOKEN) continue;
            
            Token *t = &ast->children[idx]->token;
            
            /* Skip whitespace and comments */
            if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) continue;
            
            /* If we hit a semicolon or opening brace, the type should be after it */
            if (t->type == TOKEN_PUNCTUATION) {
                if (token_matches(t, ";") || token_matches(t, "{")) {
                    /* Type should be the next non-whitespace token */
                    type_pos = skip_whitespace(ast->children, ast->child_count, idx + 1);
                    found = 1;
                    break;
                }
            }
            
            /* Keep track of potential type position */
            type_pos = idx;
        }
        
        
        /* If we didn't find a ; or {, use the beginning */
        if (!found && type_pos == 0) {
            type_pos = skip_whitespace(ast->children, ast->child_count, 0);
        }
        
        if (type_pos >= i || !ast->children[type_pos]) {
            free(cleanup_func);
            continue;
        }
        
        /* Insert __attribute__((cleanup(func))) before the type */
        /* Note: cleanup function must have signature: void func(void **ptr) */
        char attr_buf[256];
        int n = snprintf(attr_buf, sizeof(attr_buf), "__attribute__((cleanup(%s))) ", cleanup_func);
        if (n < 0 || n >= (int)sizeof(attr_buf)) {
            free(cleanup_func);
            continue;
        }
        
        /* Prepend the attribute to the type token */
        Token *type_tok = &ast->children[type_pos]->token;
        if (!type_tok->text) {
            free(cleanup_func);
            continue;
        }
        
        
        size_t new_len = strlen(attr_buf) + type_tok->length + 1;
        char *new_text = malloc(new_len);
        if (!new_text) {
            free(cleanup_func);
            continue;
        }
        
        snprintf(new_text, new_len, "%s%s", attr_buf, type_tok->text);
        free(type_tok->text);
        type_tok->text = new_text;
        type_tok->length = strlen(new_text);
        
        
        /* Replace the #defer token with just a semicolon */
        free(tok->text);
        tok->text = strdup(";");
        tok->length = 1;
        tok->type = TOKEN_PUNCTUATION;
        
        free(cleanup_func);
    }
    
}
