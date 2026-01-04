/*
 * CZar - C semantic authority layer
 * Log expansion module (transpiler/log_expand.c)
 *
 * Inserts #line directives before Log calls to ensure correct source locations.
 */

#define _POSIX_C_SOURCE 200809L

#include "log_expand.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Check if token text matches */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) return 0;
    return strcmp(token->text, text) == 0;
}

/* Check if token text starts with prefix */
static int token_text_starts_with(Token *token, const char *prefix) {
    if (!token || !token->text || !prefix) return 0;
    return strncmp(token->text, prefix, strlen(prefix)) == 0;
}

/* Skip whitespace, comments, and empty tokens */
static size_t skip_whitespace(ASTNode **children, size_t count, size_t start) {
    for (size_t i = start; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *token = &children[i]->token;
        TokenType type = token->type;
        /* Skip whitespace, comments, and empty tokens (from method transformation) */
        if (type == TOKEN_WHITESPACE || type == TOKEN_COMMENT || 
            !token->text || token->length == 0 || token->text[0] == '\0') {
            continue;
        }
        return i;
    }
    return count;
}

/* Insert a #line directive token before the specified index */
static void insert_line_directive(ASTNode *ast, size_t index, const char *filename, int line) {
    if (!ast || index > ast->child_count) return;
    
    /* Create #line directive string */
    char line_directive[512];
    snprintf(line_directive, sizeof(line_directive), "\n#line %d \"%s\"\n", line, filename);
    
    /* Create new token node for the directive */
    ASTNode *directive_node = malloc(sizeof(ASTNode));
    if (!directive_node) return;
    
    directive_node->type = AST_TOKEN;
    directive_node->token.type = TOKEN_PREPROCESSOR;
    directive_node->token.text = strdup(line_directive);
    directive_node->token.length = strlen(line_directive);
    directive_node->token.line = line;
    directive_node->token.column = 1;
    directive_node->child_count = 0;
    directive_node->children = NULL;
    
    if (!directive_node->token.text) {
        free(directive_node);
        return;
    }
    
    /* Expand children array to make room */
    ASTNode **new_children = realloc(ast->children, 
                                     (ast->child_count + 1) * sizeof(ASTNode*));
    if (!new_children) {
        free(directive_node->token.text);
        free(directive_node);
        return;
    }
    
    ast->children = new_children;
    
    /* Shift everything from index onwards by 1 */
    for (size_t i = ast->child_count; i > index; i--) {
        ast->children[i] = ast->children[i - 1];
    }
    
    /* Insert the directive */
    ast->children[index] = directive_node;
    ast->child_count++;
}

/* Expand Log calls to include correct source location via #line directives */
void transpiler_expand_log_calls(ASTNode *ast, const char *filename) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT || !filename) {
        return;
    }
    
    /* Scan for Log_* call patterns (after method transformation) */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        if (ast->children[i]->token.type != TOKEN_IDENTIFIER) continue;
        
        Token *tok = &ast->children[i]->token;
        
        /* Check if this is a Log method call (Log_verbose, Log_debug, etc.) */
        if (token_text_starts_with(tok, "Log_")) {
            /* Found Log_* identifier, check for ( after it */
            size_t j = skip_whitespace(ast->children, ast->child_count, i + 1);
            if (j >= ast->child_count) continue;
            if (ast->children[j]->type != AST_TOKEN) continue;
            if (!token_text_equals(&ast->children[j]->token, "(")) continue;
            
            /* This is a Log function call - insert #line directive before it */
            int line = tok->line;
            insert_line_directive(ast, i, filename, line);
            
            /* Skip past the directive we just inserted */
            i++;
        }
    }
}
