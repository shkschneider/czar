/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Handles mutability transformations:
 * - Everything is immutable (const) by default
 * - 'mut' keyword makes things mutable
 * - Transform 'mut Type' to 'Type' (strip mut)
 * - Transform 'Type' to 'const Type' (add const)
 * 
 * Strategy:
 * 1. Scan for 'mut' keyword followed by type, remove 'mut'
 * 2. Scan for type declarations without 'mut', add 'const'
 * 3. Handle pointers: both pointer and pointee get const
 * 4. Special case: struct methods - self is always mutable
 */

#include "../cz.h"
#include "mutability.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Known type keywords to check for const insertion */
static const char *type_keywords[] = {
    /* C standard types */
    "void", "char", "short", "int", "long", "float", "double",
    "signed", "unsigned",
    /* C stdint types */
    "int8_t", "int16_t", "int32_t", "int64_t",
    "uint8_t", "uint16_t", "uint32_t", "uint64_t",
    "size_t", "ptrdiff_t",
    /* CZar types (before transformation) */
    "i8", "i16", "i32", "i64",
    "u8", "u16", "u32", "u64",
    "f32", "f64",
    "isize", "usize",
    "bool",
    NULL
};

/* Check if token text matches */
static int token_equals(Token *token, const char *text) {
    return token && token->text && text && strcmp(token->text, text) == 0;
}

/* Check if identifier is a known type keyword */
static int is_type_keyword(const char *text) {
    if (!text) return 0;
    for (int i = 0; type_keywords[i] != NULL; i++) {
        if (strcmp(text, type_keywords[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

/* Check if token is a type identifier (keyword or struct name) */
__attribute__((unused)) static int is_type_identifier(Token *token) {
    if (!token || token->type != TOKEN_IDENTIFIER) {
        return 0;
    }
    /* Check known type keywords */
    if (is_type_keyword(token->text)) {
        return 1;
    }
    /* For now, only recognize known types to be safe */
    /* Struct types and user-defined types will need more context */
    return 0;
}

/* Skip whitespace and comments */
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

/* Look backward skipping whitespace */
static int find_prev_token(ASTNode **children, size_t current, size_t *result) {
    if (current == 0) return 0;
    
    for (int i = (int)current - 1; i >= 0; i--) {
        if (children[i]->type != AST_TOKEN) continue;
        TokenType type = children[i]->token.type;
        if (type == TOKEN_WHITESPACE || type == TOKEN_COMMENT) continue;
        *result = (size_t)i;
        return 1;
    }
    return 0;
}

/* Create a new token node */
__attribute__((unused)) static ASTNode *create_token_node(const char *text, TokenType type) {
    ASTNode *node = malloc(sizeof(ASTNode));
    if (!node) return NULL;
    
    node->type = AST_TOKEN;
    node->children = NULL;
    node->child_count = 0;
    node->child_capacity = 0;
    
    node->token.type = type;
    node->token.text = strdup(text);
    node->token.length = strlen(text);
    node->token.line = 0;
    node->token.column = 0;
    
    if (!node->token.text) {
        free(node);
        return NULL;
    }
    
    return node;
}

/* Insert a node at position in AST children */
__attribute__((unused)) static int insert_node_at(ASTNode *ast, size_t pos, ASTNode *new_node) {
    if (!ast || !new_node || pos > ast->child_count) {
        return 0;
    }
    
    /* Ensure capacity */
    if (ast->child_count >= ast->child_capacity) {
        size_t new_capacity = ast->child_capacity == 0 ? 16 : ast->child_capacity * 2;
        ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
        if (!new_children) {
            return 0;
        }
        ast->children = new_children;
        ast->child_capacity = new_capacity;
    }
    
    /* Shift elements to make room */
    for (size_t i = ast->child_count; i > pos; i--) {
        ast->children[i] = ast->children[i - 1];
    }
    
    /* Insert new node */
    ast->children[pos] = new_node;
    ast->child_count++;
    
    return 1;
}

/* Mark a token for deletion by replacing its text with empty string */
static void mark_for_deletion(ASTNode *node) {
    if (node && node->type == AST_TOKEN && node->token.text) {
        free(node->token.text);
        node->token.text = strdup("");
        node->token.length = 0;
    }
}

/* Check if we're in a struct method declaration context (looking for . before method name) */
__attribute__((unused)) static int is_in_method_declaration(ASTNode **children, size_t count, size_t type_pos) {
    /* Look ahead for pattern: Type.method_name( */
    size_t i = skip_whitespace(children, count, type_pos + 1);
    if (i >= count) return 0;
    if (!token_equals(&children[i]->token, ".")) return 0;
    
    i = skip_whitespace(children, count, i + 1);
    if (i >= count) return 0;
    if (children[i]->token.type != TOKEN_IDENTIFIER) return 0;
    
    i = skip_whitespace(children, count, i + 1);
    if (i >= count) return 0;
    if (!token_equals(&children[i]->token, "(")) return 0;
    
    return 1;
}

/* Check if context suggests this is a declaration (not a call or expression) */
__attribute__((unused)) static int is_declaration_context(ASTNode **children, size_t count __attribute__((unused)), size_t type_pos) {
    /* Look backward for declaration indicators */
    size_t prev_idx;
    if (!find_prev_token(children, type_pos, &prev_idx)) {
        return 1; /* At start, likely a declaration */
    }
    
    Token *prev = &children[prev_idx]->token;
    
    /* After these keywords, we expect a declaration */
    if (token_equals(prev, "static") || token_equals(prev, "extern") ||
        token_equals(prev, "const") || token_equals(prev, "volatile") ||
        token_equals(prev, "{") || token_equals(prev, ";") ||
        token_equals(prev, ",") || token_equals(prev, "(")) {
        return 1;
    }
    
    /* After return/cast/operators, not a declaration */
    if (token_equals(prev, "return") || token_equals(prev, "=") ||
        token_equals(prev, "+") || token_equals(prev, "-") ||
        token_equals(prev, "*") || token_equals(prev, "/")) {
        return 0;
    }
    
    return 1;
}

/* Transform mutability in AST */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    ASTNode **children = ast->children;
    size_t count = ast->child_count;
    
    /* Pass 1: Find and remove 'mut' keywords */
    /* For now, we only strip 'mut' and don't automatically add 'const' */
    /* This is a simpler first implementation to avoid breaking existing code */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (children[i]->token.type != TOKEN_IDENTIFIER) continue;
        
        Token *tok = &children[i]->token;
        
        /* Check if this is 'mut' keyword */
        if (!token_equals(tok, "mut")) continue;
        
        /* Found 'mut' - look for following type */
        size_t j = skip_whitespace(children, count, i + 1);
        if (j >= count) continue;
        
        if (children[j]->type == AST_TOKEN && 
            children[j]->token.type == TOKEN_IDENTIFIER) {
            /* This is the type following 'mut' - it's already mutable */
            /* Remove the 'mut' keyword */
            mark_for_deletion(children[i]);
        }
    }
    
    /* TODO: Pass 2: Add 'const' to type identifiers that don't have 'mut' */
    /* This requires more sophisticated context analysis to avoid breaking things */
    /* For now, everything without 'mut' remains as-is (C default is mutable) */
}
