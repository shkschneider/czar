/*
 * CZar - C semantic authority layer
 * Pragma parser implementation (transpiler/pragma.c)
 *
 * Parses and handles #pragma czar directives.
 */

#define _POSIX_C_SOURCE 200809L

#include "pragma.h"
#include <string.h>
#include <ctype.h>
#include <stdlib.h>

/* Initialize pragma context with defaults */
void pragma_context_init(PragmaContext *ctx) {
    if (!ctx) return;
    ctx->debug_mode = 1;  /* Default: debug on */
}

/* Check if string starts with prefix (case insensitive for whitespace-trimmed strings) */
static int starts_with(const char *str, const char *prefix) {
    if (!str || !prefix) return 0;
    while (*str && isspace((unsigned char)*str)) str++;
    return strncmp(str, prefix, strlen(prefix)) == 0;
}

/* Extract word after prefix, skipping whitespace */
static const char *extract_word_after(const char *str, const char *prefix) {
    if (!starts_with(str, prefix)) return NULL;
    str += strlen(prefix);
    while (*str && isspace((unsigned char)*str)) str++;
    return str;
}

/* Parse a single #pragma czar directive */
static void parse_pragma_czar(const char *pragma_text, PragmaContext *ctx) {
    if (!pragma_text || !ctx) return;
    
    /* Skip leading whitespace and # */
    while (*pragma_text && (isspace((unsigned char)*pragma_text) || *pragma_text == '#')) {
        pragma_text++;
    }
    
    /* Check for "pragma" keyword */
    if (!starts_with(pragma_text, "pragma")) return;
    pragma_text = extract_word_after(pragma_text, "pragma");
    if (!pragma_text) return;
    
    /* Check for "czar" keyword */
    if (!starts_with(pragma_text, "czar")) return;
    pragma_text = extract_word_after(pragma_text, "czar");
    if (!pragma_text) return;
    
    /* Parse "debug" directive */
    if (starts_with(pragma_text, "debug")) {
        pragma_text = extract_word_after(pragma_text, "debug");
        if (!pragma_text) return;
        
        /* Parse true/false */
        if (starts_with(pragma_text, "true")) {
            ctx->debug_mode = 1;
        } else if (starts_with(pragma_text, "false")) {
            ctx->debug_mode = 0;
        }
        /* Else: ignore invalid values, keep current setting */
    }
    /* Other pragma directives can be added here in the future */
}

/* Parse and apply #pragma czar directives from AST */
void transpiler_parse_pragmas(ASTNode *ast, PragmaContext *ctx) {
    if (!ast || !ctx) return;
    
    /* Only process translation unit nodes */
    if (ast->type != AST_TRANSLATION_UNIT) return;
    
    /* Scan all tokens looking for preprocessor directives */
    for (size_t i = 0; i < ast->child_count; i++) {
        ASTNode *child = ast->children[i];
        if (!child || child->type != AST_TOKEN) continue;
        
        Token *token = &child->token;
        if (token->type != TOKEN_PREPROCESSOR) continue;
        if (!token->text) continue;
        
        /* Check if this is a #pragma czar directive */
        if (strstr(token->text, "pragma") && strstr(token->text, "czar")) {
            parse_pragma_czar(token->text, ctx);
        }
    }
}
