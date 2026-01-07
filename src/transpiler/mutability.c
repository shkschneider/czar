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
static ASTNode *create_token_node(const char *text, TokenType type) {
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
static int insert_node_at(ASTNode *ast, size_t pos, ASTNode *new_node) {
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

/* Transform mutability in AST */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    ASTNode **children = ast->children;
    size_t count = ast->child_count;
    
    /* Pass 1: Mark types following 'mut' for mutable access, and mark 'mut' for deletion */
    int *is_mutable = calloc(count, sizeof(int));
    if (!is_mutable) return; /* Out of memory */
    
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
            /* Mark the type at position j as mutable */
            is_mutable[j] = 1;
            /* Mark 'mut' for deletion */
            mark_for_deletion(children[i]);
        }
    }
    
    /* Pass 2: Add 'const' to type identifiers that are not marked as mutable */
    /* For now, we'll be very conservative and only add const to function parameters */
    /* We detect function parameters by looking for the pattern: type identifier( */
    
    /* Build a list of positions where we need to insert const, then insert in reverse */
    size_t *insert_positions = malloc(count * sizeof(size_t));
    size_t insert_count = 0;
    
    if (!insert_positions) {
        free(is_mutable);
        return; /* Out of memory */
    }
    
    /* Scan for function declarations and mark parameter types for const insertion */
    for (size_t i = 0; i + 2 < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok_type = &children[i]->token;
        
        /* Check if this looks like: type identifier( pattern */
        /* This is more reliable for detecting function declarations */
        if (tok_type->type != TOKEN_IDENTIFIER) continue;
        
        /* Check if it's a type keyword (could also be return type) */
        if (!is_type_keyword(tok_type->text)) continue;
        
        /* Look ahead for identifier */
        size_t name_idx = skip_whitespace(children, count, i + 1);
        if (name_idx >= count) continue;
        if (children[name_idx]->type != AST_TOKEN) continue;
        if (children[name_idx]->token.type != TOKEN_IDENTIFIER) continue;
        
        /* Look ahead for ( */
        size_t paren_idx = skip_whitespace(children, count, name_idx + 1);
        if (paren_idx >= count) continue;
        if (children[paren_idx]->type != AST_TOKEN) continue;
        if (!token_equals(&children[paren_idx]->token, "(")) continue;
        
        /* Found function declaration! Now scan the parameter list */
        int depth = 1;
        for (size_t j = paren_idx + 1; j < count && depth > 0; j++) {
            if (children[j]->type != AST_TOKEN) continue;
            Token *param_tok = &children[j]->token;
            
            if (param_tok->type == TOKEN_PUNCTUATION) {
                if (token_equals(param_tok, "(")) depth++;
                else if (token_equals(param_tok, ")")) {
                    depth--;
                    if (depth == 0) break; /* End of parameter list */
                }
            }
            
            /* Check if this is a parameter type */
            if (param_tok->type == TOKEN_IDENTIFIER && is_type_keyword(param_tok->text)) {
                /* Skip void */
                if (token_equals(param_tok, "void")) continue;
                
                /* Check if this is a pointer type - look ahead for * */
                size_t next_idx = skip_whitespace(children, count, j + 1);
                int is_pointer = 0;
                if (next_idx < count && children[next_idx]->type == AST_TOKEN) {
                    if (token_equals(&children[next_idx]->token, "*")) {
                        is_pointer = 1;
                    }
                }
                
                /* Skip pointers for now - they need special handling */
                if (is_pointer) continue;
                
                /* Skip if marked as mutable */
                if (is_mutable[j]) continue;
                
                /* Skip if already has const */
                size_t prev_idx;
                if (find_prev_token(children, j, &prev_idx)) {
                    if (token_equals(&children[prev_idx]->token, "const")) {
                        continue;
                    }
                }
                
                /* Add to insert list */
                insert_positions[insert_count++] = j;
            }
        }
    }
    
    /* Insert const tokens in reverse order to maintain position validity */
    for (int idx = (int)insert_count - 1; idx >= 0; idx--) {
        size_t pos = insert_positions[idx];
        ASTNode *const_node = create_token_node("const", TOKEN_IDENTIFIER);
        ASTNode *space_node = create_token_node(" ", TOKEN_WHITESPACE);
        
        if (const_node && space_node) {
            insert_node_at(ast, pos, const_node);
            insert_node_at(ast, pos + 1, space_node);
        } else {
            /* Cleanup on failure */
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
    
    free(insert_positions);
    free(is_mutable);
}
