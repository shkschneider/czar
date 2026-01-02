/*
 * CZar - C semantic authority layer
 * Member access transformation implementation (transpiler/autodereference.c)
 *
 * Handles auto-dereference of pointers when using . operator.
 * This transforms pointer.member to pointer->member automatically.
 */

#define _POSIX_C_SOURCE 200809L

#include "autodereference.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

/* Maximum number of identifiers we can track */
#define MAX_TRACKED_IDENTIFIERS 1024

/* Search window for looking ahead/back in token stream */
#define TOKEN_SEARCH_WINDOW 5

/* Tracked identifier (variable/parameter that is a pointer) */
typedef struct {
    char *name;
    int is_pointer;
    size_t declaration_index; /* Position in token stream where this was declared */
} TrackedIdentifier;

/* Global state for tracking identifiers */
static TrackedIdentifier tracked_ids[MAX_TRACKED_IDENTIFIERS];
static size_t tracked_count = 0;

/* Add an identifier to tracking */
static void track_identifier(const char *name, int is_pointer, size_t position) {
    if (tracked_count >= MAX_TRACKED_IDENTIFIERS) {
        return; /* Tracking limit reached */
    }
    
    /* Check if already tracked - update if so (keep the earliest declaration) */
    for (size_t i = 0; i < tracked_count; i++) {
        if (tracked_ids[i].name && strcmp(tracked_ids[i].name, name) == 0) {
            /* Only update if this is an earlier declaration */
            if (position < tracked_ids[i].declaration_index) {
                tracked_ids[i].is_pointer = is_pointer;
                tracked_ids[i].declaration_index = position;
            }
            return;
        }
    }
    
    /* Add new tracking entry */
    char *name_copy = strdup(name);
    if (!name_copy) {
        return; /* Memory allocation failed, cannot track */
    }
    
    tracked_ids[tracked_count].name = name_copy;
    tracked_ids[tracked_count].is_pointer = is_pointer;
    tracked_ids[tracked_count].declaration_index = position;
    tracked_count++;
}

/* Check if an identifier is tracked as a pointer at a given position */
static int is_tracked_pointer_at(const char *name, size_t position) {
    for (size_t i = 0; i < tracked_count; i++) {
        if (tracked_ids[i].name && strcmp(tracked_ids[i].name, name) == 0) {
            /* Only consider it a pointer if this usage is after the declaration */
            if (position > tracked_ids[i].declaration_index) {
                return tracked_ids[i].is_pointer;
            }
        }
    }
    return 0; /* Not tracked or not a pointer or used before declaration */
}

/* Clear tracking (called at start of each translation unit) */
static void clear_tracking(void) {
    for (size_t i = 0; i < tracked_count; i++) {
        if (tracked_ids[i].name) {
            free(tracked_ids[i].name);
            tracked_ids[i].name = NULL;
        }
    }
    tracked_count = 0;
}

/* Check if a token represents a pointer type (contains '*') */
static int token_is_pointer_type(const Token *token) {
    if (!token || !token->text) {
        return 0;
    }
    return strchr(token->text, '*') != NULL;
}

/* Scan AST to track pointer declarations and parameters */
static void scan_for_pointers(ASTNode *node) {
    if (!node) {
        return;
    }
    
    if (node->type == AST_TRANSLATION_UNIT) {
        int paren_depth = 0;
        int in_function_params = 0;
        int brace_depth = 0;
        
        /* Track brace depth to know when we're in a function body */
        /* Track paren depth to know when we're in function parameters */
        /* Only track pointer parameters from function declarations */
        
        for (size_t i = 0; i < node->child_count; i++) {
            ASTNode *child = node->children[i];
            if (child->type != AST_TOKEN) continue;
            
            Token *tok = &child->token;
            
            /* Track braces for scope */
            if (tok->type == TOKEN_PUNCTUATION) {
                if (strcmp(tok->text, "{") == 0) {
                    brace_depth++;
                } else if (strcmp(tok->text, "}") == 0) {
                    brace_depth--;
                }
            }
            
            /* Track parentheses */
            if (tok->type == TOKEN_PUNCTUATION) {
                if (strcmp(tok->text, "(") == 0) {
                    paren_depth++;
                    /* Check if this might be function parameters */
                    /* Look back to see if there's an identifier before ( */
                    if (i > 0 && brace_depth == 0) {
                        /* Skip back over whitespace */
                        for (int j = (int)i - 1; j >= 0 && j >= (int)i - TOKEN_SEARCH_WINDOW; j--) {
                            ASTNode *prev = node->children[j];
                            if (prev->type != AST_TOKEN) continue;
                            Token *prevtok = &prev->token;
                            if (prevtok->type == TOKEN_WHITESPACE) continue;
                            if (prevtok->type == TOKEN_IDENTIFIER) {
                                /* Found identifier before (, likely a function declaration */
                                in_function_params = 1;
                            }
                            break;
                        }
                    }
                } else if (strcmp(tok->text, ")") == 0) {
                    paren_depth--;
                    if (paren_depth == 0) {
                        in_function_params = 0;
                    }
                }
            }
            
            /* Only track pointers in function parameter lists */
            if (in_function_params && paren_depth > 0 && brace_depth == 0) {
                /* Look for pointer operator * */
                if (tok->type == TOKEN_OPERATOR && token_is_pointer_type(tok)) {
                    /* Look ahead for identifier, skipping whitespace */
                    for (size_t j = i + 1; j < node->child_count && j < i + TOKEN_SEARCH_WINDOW; j++) {
                        ASTNode *next_node = node->children[j];
                        if (next_node->type != AST_TOKEN) continue;
                        
                        Token *next = &next_node->token;
                        if (next->type == TOKEN_WHITESPACE) {
                            continue; /* Skip whitespace */
                        } else if (next->type == TOKEN_IDENTIFIER) {
                            track_identifier(next->text, 1, j);
                            break;
                        } else {
                            break; /* Hit something else, stop looking */
                        }
                    }
                }
            }
        }
    }
}

/* Transform member access operators */
static void transform_autodereference_node(ASTNode *node) {
    if (!node || node->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    /* Look for patterns: identifier . identifier */
    for (size_t i = 0; i < node->child_count; i++) {
        if (i + 2 >= node->child_count) {
            continue; /* Need at least 3 tokens for member access */
        }
        
        ASTNode *left_node = node->children[i];
        ASTNode *op_node = node->children[i + 1];
        ASTNode *right_node = node->children[i + 2];
        
        /* Check if this is a member access pattern */
        if (left_node->type == AST_TOKEN && op_node->type == AST_TOKEN && right_node->type == AST_TOKEN) {
            Token *left = &left_node->token;
            Token *op = &op_node->token;
            Token *right = &right_node->token;
            
            /* Check for: identifier . identifier */
            if (left->type == TOKEN_IDENTIFIER && 
                op->type == TOKEN_OPERATOR && 
                op->text && strcmp(op->text, ".") == 0 &&
                right->type == TOKEN_IDENTIFIER) {
                
                /* Check if left side is a tracked pointer at this position */
                if (is_tracked_pointer_at(left->text, i)) {
                    /* Transform . to -> */
                    char *new_text = strdup("->");
                    if (new_text) {
                        free(op->text);
                        op->text = new_text;
                        op->length = strlen(new_text);
                    }
                    /* If strdup fails, leave the original text unchanged */
                }
            }
        }
    }
}

/* Main entry point for member access transformation */
void transpiler_transform_autodereference(ASTNode *ast) {
    if (!ast) {
        return;
    }
    
    /* Clear previous tracking state */
    clear_tracking();
    
    /* First pass: scan for pointer declarations */
    scan_for_pointers(ast);
    
    /* Second pass: transform member access operators */
    transform_autodereference_node(ast);
}
