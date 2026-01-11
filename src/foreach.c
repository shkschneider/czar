/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Transforms foreach-like syntax to portable C for loops.
 *
 * Currently implemented:
 * - Range iteration: for (type var : start..end) → for (mut type var = start; var <= end; var++)
 * - Array with index: for (type idx, type val : array) → for (mut type idx = 0; idx < sizeof(array)/sizeof(array[0]); idx++) { type val = array[idx]; ... }
 * - Array without index: for (_, type val : array) → for (mut size_t _cz_idx = 0; _cz_idx < sizeof(array)/sizeof(array[0]); _cz_idx++) { type val = array[_cz_idx]; ... }
 *
 * Planned (TODO):
 * - String iteration: for (char c : str) → for (size_t _i = 0; str[_i] != '\0'; _i++) { char c = str[_i]; ... }
 * - Single variable array: for (type val : array) → similar to (_, type val : array)
 *
 * Notes:
 * - The lexer parses "0..9" as three tokens: "0", ".", ".9" (where ".9" is treated as a decimal)
 * - Range variables are automatically marked as `mut` since they need to be incremented
 * - Array index variables are automatically marked as `mut`
 * - Works with both CZar types (u8, u32, etc.) and standard C types (int, char, etc.)
 * - The user explicitly provides the value type, so no type inference is needed
 */

#include "foreach.h"
#include "errors.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>

/* Maximum size for temporary token text buffers */
#define MAX_TOKEN_BUFFER_SIZE 256

/* Default loop variable name when var name is unavailable */
#define DEFAULT_LOOP_VAR "i"

/* Helper: Check if token equals string */
static int token_equals(const Token *tok, const char *str) {
    return tok && tok->text && strcmp(tok->text, str) == 0;
}

/* Helper: Skip whitespace and comment tokens */
static size_t skip_whitespace(ASTNode_t **children, size_t count, size_t start) {
    while (start < count && children[start]->type == AST_TOKEN) {
        Token *tok = &children[start]->token;
        if (tok->type != TOKEN_WHITESPACE && tok->type != TOKEN_COMMENT) {
            break;
        }
        start++;
    }
    return start;
}

/* Helper: Duplicate a string */
static char *strdup_safe(const char *str) {
    if (!str) return NULL;
    size_t len = strlen(str);
    char *dup = malloc(len + 1);
    if (dup) {
        memcpy(dup, str, len);
        dup[len] = '\0';
    }
    return dup;
}

/* Helper: Mark a token for deletion by replacing its text with empty string */
static void mark_for_deletion(ASTNode_t *node) {
    if (node && node->type == AST_TOKEN && node->token.text) {
        free(node->token.text);
        node->token.text = strdup_safe("");
        node->token.length = 0;
    }
}

/* Helper: Create a new token with specific text */
static ASTNode_t *create_token_node(const char *text, TokenType type, int line, int column) {
    ASTNode_t *node = calloc(1, sizeof(ASTNode_t));
    if (!node) return NULL;
    
    node->type = AST_TOKEN;
    node->token.type = type;
    node->token.text = strdup_safe(text);
    node->token.length = text ? strlen(text) : 0;
    node->token.line = line;
    node->token.column = column;
    node->children = NULL;
    node->child_count = 0;
    node->child_capacity = 0;
    
    return node;
}

/* Helper: Insert nodes after a position */
static void insert_nodes_after(ASTNode_t *ast, size_t pos, ASTNode_t **new_nodes, size_t new_count) {
    if (!ast || !new_nodes || new_count == 0) return;
    
    /* Expand capacity if needed */
    size_t required_capacity = ast->child_count + new_count;
    if (required_capacity > ast->child_capacity) {
        size_t new_capacity = ast->child_capacity * 2;
        if (new_capacity < required_capacity) {
            new_capacity = required_capacity;
        }
        ASTNode_t **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode_t*));
        if (!new_children) {
            /* Memory allocation failed - cannot proceed with insertion */
            return;
        }
        ast->children = new_children;
        ast->child_capacity = new_capacity;
    }
    
    /* Shift existing nodes */
    for (size_t i = ast->child_count; i > pos + 1; i--) {
        ast->children[i + new_count - 1] = ast->children[i - 1];
    }
    
    /* Insert new nodes */
    for (size_t i = 0; i < new_count; i++) {
        ast->children[pos + 1 + i] = new_nodes[i];
    }
    
    ast->child_count += new_count;
}

/* Helper: Replace token text */
static void replace_token_text(Token *tok, const char *new_text) {
    if (!tok) return;
    if (tok->text) {
        free(tok->text);
    }
    tok->text = strdup_safe(new_text);
    tok->length = new_text ? strlen(new_text) : 0;
}

/* Helper: Check if we're looking at a foreach pattern */
static int is_foreach_pattern(ASTNode_t **children, size_t count, size_t for_idx, size_t *colon_idx) {
    /* Look for pattern: for ( ... : ... ) */
    size_t idx = skip_whitespace(children, count, for_idx + 1);
    if (idx >= count || !token_equals(&children[idx]->token, "(")) {
        return 0;
    }
    
    /* Find the colon and closing paren */
    int depth = 1;
    int found_colon = 0;
    size_t col_idx = 0;
    
    for (size_t i = idx + 1; i < count && depth > 0; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;
        
        if (token_equals(tok, "(")) {
            depth++;
        } else if (token_equals(tok, ")")) {
            depth--;
        } else if (depth == 1 && token_equals(tok, ":") && !found_colon) {
            found_colon = 1;
            col_idx = i;
        }
    }
    
    if (found_colon && colon_idx) {
        *colon_idx = col_idx;
    }
    
    return found_colon;
}

/* Transform: for (type var : collection) patterns */
static void transform_foreach_loop(ASTNode_t *ast, size_t for_idx, const char *filename, const char *source) {
    ASTNode_t **children = ast->children;
    size_t count = ast->child_count;
    
    /* Find colon position */
    size_t colon_idx = 0;
    if (!is_foreach_pattern(children, count, for_idx, &colon_idx)) {
        return;
    }
    
    /* Find opening paren */
    size_t paren_idx = skip_whitespace(children, count, for_idx + 1);
    if (paren_idx >= count || !token_equals(&children[paren_idx]->token, "(")) {
        return;
    }
    
    /* Parse the left side of colon (variable declarations) */
    /* Can be: type var, type idx, type val, or _, var */
    size_t left_start = skip_whitespace(children, count, paren_idx + 1);
    size_t left_end = colon_idx;
    
    /* Skip backwards from colon to find last non-whitespace */
    while (left_end > left_start && children[left_end - 1]->type == AST_TOKEN &&
           (children[left_end - 1]->token.type == TOKEN_WHITESPACE ||
            children[left_end - 1]->token.type == TOKEN_COMMENT)) {
        left_end--;
    }
    
    /* Parse right side of colon (collection or range) */
    size_t right_start = skip_whitespace(children, count, colon_idx + 1);
    
    /* Find closing paren */
    size_t close_paren_idx = right_start;
    int depth = 1;
    for (size_t i = paren_idx + 1; i < count && depth > 0; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (token_equals(&children[i]->token, "(")) depth++;
        else if (token_equals(&children[i]->token, ")")) {
            depth--;
            if (depth == 0) {
                close_paren_idx = i;
                break;
            }
        }
    }
    
    /* Check if right side is a range (contains ..) */
    /* Note: The lexer parses "0..5" as "0", ".", ".5" so we need to handle this */
    int is_range = 0;
    for (size_t i = right_start; i < close_paren_idx; i++) {
        /* Look for pattern: . followed by number starting with . */
        if (children[i]->type == AST_TOKEN && 
            token_equals(&children[i]->token, ".") &&
            i + 1 < close_paren_idx && 
            children[i + 1]->type == AST_TOKEN &&
            children[i + 1]->token.type == TOKEN_NUMBER &&
            children[i + 1]->token.text && 
            children[i + 1]->token.text[0] == '.') {
            is_range = 1;
            break;
        }
        /* Also look for traditional .. pattern */
        if (children[i]->type == AST_TOKEN && 
            token_equals(&children[i]->token, ".") &&
            i + 1 < close_paren_idx && 
            children[i + 1]->type == AST_TOKEN &&
            token_equals(&children[i + 1]->token, ".")) {
            is_range = 1;
            break;
        }
    }
    
    /* Build the replacement for loop */
    /* This is complex - we need to:
     * 1. Parse variable declarations on left
     * 2. Determine collection type on right
     * 3. Generate appropriate C for loop
     */
    
    if (is_range) {
        /* Range-based loop: for (type var : start..end) */
        /* Transform to: for (mut type var = start; var <= end; var++) */
        
        /* Extract variable declaration from left side */
        /* Find the variable name (last identifier before colon) */
        size_t var_idx = left_end - 1;
        while (var_idx > left_start && children[var_idx]->type == AST_TOKEN &&
               children[var_idx]->token.type != TOKEN_IDENTIFIER) {
            var_idx--;
        }
        
        if (var_idx >= left_start && children[var_idx]->type == AST_TOKEN &&
            children[var_idx]->token.type == TOKEN_IDENTIFIER) {
            
            /* For range-based loops, the variable must be mutable */
            /* Insert 'mut ' before the type if not already present */
            size_t type_idx = left_start;
            while (type_idx < var_idx && children[type_idx]->type == AST_TOKEN &&
                   children[type_idx]->token.type == TOKEN_WHITESPACE) {
                type_idx++;
            }
            
            /* Check if 'mut' is already there */
            int has_mut = 0;
            if (type_idx < var_idx && children[type_idx]->type == AST_TOKEN &&
                token_equals(&children[type_idx]->token, "mut")) {
                has_mut = 1;
            }
            
            /* Insert mut if not present */
            if (!has_mut && type_idx < count) {
                ASTNode_t *mut_nodes[2];
                Token *ref_tok = &children[type_idx]->token;
                mut_nodes[0] = create_token_node("mut", TOKEN_KEYWORD, ref_tok->line, ref_tok->column);
                mut_nodes[1] = create_token_node(" ", TOKEN_WHITESPACE, ref_tok->line, ref_tok->column);
                insert_nodes_after(ast, type_idx - 1, mut_nodes, 2);
                
                /* Adjust indices after insertion */
                colon_idx += 2;
                var_idx += 2;
                right_start += 2;
                close_paren_idx += 2;
                count = ast->child_count;
                children = ast->children;
            }
            
            /* Change colon to = with spaces */
            replace_token_text(&children[colon_idx]->token, " = ");
            
            /* Replace .. with ; var <= */
            /* Need to handle lexer quirk where "0..5" becomes "0", ".", ".5" */
            for (size_t i = right_start; i < close_paren_idx; i++) {
                int found_range = 0;
                
                /* Pattern 1: . followed by number starting with . (e.g., ".", ".5") */
                if (children[i]->type == AST_TOKEN && 
                    token_equals(&children[i]->token, ".") &&
                    i + 1 < close_paren_idx && 
                    children[i + 1]->type == AST_TOKEN &&
                    children[i + 1]->token.type == TOKEN_NUMBER &&
                    children[i + 1]->token.text &&
                    children[i + 1]->token.text[0] == '.') {
                    found_range = 1;
                }
                
                /* Pattern 2: Two consecutive . tokens */
                if (children[i]->type == AST_TOKEN && 
                    token_equals(&children[i]->token, ".") &&
                    i + 1 < close_paren_idx && 
                    children[i + 1]->type == AST_TOKEN &&
                    token_equals(&children[i + 1]->token, ".")) {
                    found_range = 1;
                }
                
                if (found_range) {
                    char *var_name = children[var_idx]->token.text;
                    char buf[MAX_TOKEN_BUFFER_SIZE];
                    
                    /* Replace first . with ; and space */
                    replace_token_text(&children[i]->token, "; ");
                    
                    /* Handle the second token based on its format */
                    if (children[i + 1]->token.text && children[i + 1]->token.text[0] == '.') {
                        /* It's .N, need to replace with "var <= N" */
                        const char *end_val = &children[i + 1]->token.text[1]; /* Skip the leading . */
                        /* Use snprintf and check return value to ensure no truncation */
                        int written = snprintf(buf, sizeof(buf), "%s <= %s", 
                                var_name ? var_name : DEFAULT_LOOP_VAR, end_val);
                        /* If truncated, use fallback (should not happen with reasonable identifier names) */
                        if (written < 0 || (size_t)written >= sizeof(buf)) {
                            snprintf(buf, sizeof(buf), "%s <= %s", DEFAULT_LOOP_VAR, end_val);
                        }
                    } else {
                        /* It's a second ., need to replace with "var <= " */
                        snprintf(buf, sizeof(buf), "%s <= ", var_name ? var_name : DEFAULT_LOOP_VAR);
                    }
                    replace_token_text(&children[i + 1]->token, buf);
                    
                    /* Add ; var++ before closing paren */
                    Token *before_close = &children[close_paren_idx - 1]->token;
                    int line = before_close->line;
                    int col = before_close->column;
                    
                    ASTNode_t *new_nodes[2];
                    new_nodes[0] = create_token_node("; ", TOKEN_PUNCTUATION, line, col);
                    snprintf(buf, sizeof(buf), "%s++", var_name ? var_name : DEFAULT_LOOP_VAR);
                    new_nodes[1] = create_token_node(buf, TOKEN_IDENTIFIER, line, col);
                    
                    insert_nodes_after(ast, close_paren_idx - 1, new_nodes, 2);
                    break;
                }
            }
        }
    } else {
        /* Collection-based loop: for (idx, val : array) or for (_, val : array) */
        /* Check if left side has a comma - indicating index/value pattern */
        int has_comma = 0;
        size_t comma_idx = 0;
        for (size_t i = left_start; i < left_end; i++) {
            if (children[i]->type == AST_TOKEN && token_equals(&children[i]->token, ",")) {
                has_comma = 1;
                comma_idx = i;
                break;
            }
        }
        
        if (has_comma) {
            /* Pattern: for (idx_type idx, val_type val : array) */
            /* Parse index variable (before comma) */
            size_t idx_var_idx = comma_idx - 1;
            while (idx_var_idx > left_start && children[idx_var_idx]->type == AST_TOKEN &&
                   children[idx_var_idx]->token.type == TOKEN_WHITESPACE) {
                idx_var_idx--;
            }
            
            /* Parse value variable (after comma, before colon) */
            size_t val_var_idx = left_end - 1;
            while (val_var_idx > comma_idx && children[val_var_idx]->type == AST_TOKEN &&
                   children[val_var_idx]->token.type == TOKEN_WHITESPACE) {
                val_var_idx--;
            }
            
            /* Parse value type (between comma and value variable) */
            size_t val_type_start = skip_whitespace(children, count, comma_idx + 1);
            size_t val_type_end = val_var_idx;
            
            /* Copy value type to a buffer NOW, before we mark tokens for deletion */
            /* Also check if the value type has 'mut' keyword */
            char val_type_buf[MAX_TOKEN_BUFFER_SIZE] = {0};
            size_t val_type_len = 0;
            int val_has_mut = 0;
            
            for (size_t i = val_type_start; i < val_type_end && val_type_len < MAX_TOKEN_BUFFER_SIZE - 2; i++) {
                if (children[i]->type == AST_TOKEN && children[i]->token.text &&
                    children[i]->token.text[0] != '\0') {
                    /* Check if this is the 'mut' keyword - if so, skip it */
                    if ((children[i]->token.type == TOKEN_KEYWORD || children[i]->token.type == TOKEN_IDENTIFIER) &&
                        strcmp(children[i]->token.text, "mut") == 0) {
                        val_has_mut = 1;
                        continue; /* Skip copying 'mut' */
                    }
                    
                    size_t tok_len = strlen(children[i]->token.text);
                    if (val_type_len + tok_len < MAX_TOKEN_BUFFER_SIZE - 2) {
                        memcpy(val_type_buf + val_type_len, children[i]->token.text, tok_len);
                        val_type_len += tok_len;
                    }
                }
            }
            val_type_buf[val_type_len] = '\0';
            
            /* Check if index is _ (underscore - meaning we don't want the index variable) */
            int skip_index = 0;
            if (children[idx_var_idx]->type == AST_TOKEN &&
                token_equals(&children[idx_var_idx]->token, "_")) {
                skip_index = 1;
            }
            
            if (children[idx_var_idx]->type == AST_TOKEN &&
                children[idx_var_idx]->token.type == TOKEN_IDENTIFIER &&
                children[val_var_idx]->type == AST_TOKEN &&
                children[val_var_idx]->token.type == TOKEN_IDENTIFIER) {
                
                /* Copy variable names NOW before marking for deletion */
                char idx_var_name_buf[MAX_TOKEN_BUFFER_SIZE] = {0};
                char val_var_name_buf[MAX_TOKEN_BUFFER_SIZE] = {0};
                
                if (!skip_index && children[idx_var_idx]->token.text) {
                    strncpy(idx_var_name_buf, children[idx_var_idx]->token.text, MAX_TOKEN_BUFFER_SIZE - 1);
                }
                if (children[val_var_idx]->token.text) {
                    strncpy(val_var_name_buf, children[val_var_idx]->token.text, MAX_TOKEN_BUFFER_SIZE - 1);
                }
                
                char *idx_var_name = skip_index ? NULL : idx_var_name_buf;
                char *val_var_name = val_var_name_buf;
                char buf[MAX_TOKEN_BUFFER_SIZE];
                
                /* Get the collection name (right side of colon) */
                size_t collection_start = right_start;
                size_t collection_end = close_paren_idx;
                /* Skip backwards to find last non-whitespace */
                while (collection_end > collection_start && children[collection_end - 1]->type == AST_TOKEN &&
                       children[collection_end - 1]->token.type == TOKEN_WHITESPACE) {
                    collection_end--;
                }
                
                /* Build collection name by concatenating tokens */
                char collection_name[MAX_TOKEN_BUFFER_SIZE] = {0};
                size_t coll_len = 0;
                for (size_t i = collection_start; i < collection_end && coll_len < MAX_TOKEN_BUFFER_SIZE - 1; i++) {
                    if (children[i]->type == AST_TOKEN && children[i]->token.text) {
                        size_t tok_len = strlen(children[i]->token.text);
                        if (coll_len + tok_len < MAX_TOKEN_BUFFER_SIZE - 1) {
                            memcpy(collection_name + coll_len, children[i]->token.text, tok_len);
                            coll_len += tok_len;
                        }
                    }
                }
                collection_name[coll_len] = '\0';
                
                /* Use a loop index variable - either the specified one or generate one */
                const char *loop_idx_var = skip_index ? "_cz_idx" : idx_var_name;
                
                /* Transform the for header */
                /* Build new tokens FIRST, then delete old ones */
                
                /* Build the new tokens */
                Token *ref_tok = &children[paren_idx]->token;
                int line = ref_tok->line;
                int col = ref_tok->column;
                
                ASTNode_t **new_tokens = malloc(sizeof(ASTNode_t*) * 50); /* Allocate enough space */
                size_t new_token_count = 0;
                
                if (!new_tokens) {
                    return; /* Out of memory */
                }
                
                /* Add: mut */
                if (!skip_index) {
                    /* Add mut keyword */
                    new_tokens[new_token_count++] = create_token_node("mut", TOKEN_KEYWORD, line, col);
                    new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                    
                    /* Copy the index type and variable tokens */
                    for (size_t i = left_start; i < comma_idx; i++) {
                        if (children[i]->type == AST_TOKEN && children[i]->token.text &&
                            children[i]->token.text[0] != '\0') {
                            /* Clone the token */
                            ASTNode_t *clone = create_token_node(children[i]->token.text,
                                                                 children[i]->token.type,
                                                                 line, col);
                            if (clone) {
                                new_tokens[new_token_count++] = clone;
                            }
                        }
                    }
                } else {
                    /* Generate: mut size_t _cz_idx */
                    new_tokens[new_token_count++] = create_token_node("mut", TOKEN_KEYWORD, line, col);
                    new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                    new_tokens[new_token_count++] = create_token_node("size_t", TOKEN_IDENTIFIER, line, col);
                    new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                    new_tokens[new_token_count++] = create_token_node("_cz_idx", TOKEN_IDENTIFIER, line, col);
                }
                
                /* Add: = 0; */
                new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                new_tokens[new_token_count++] = create_token_node("=", TOKEN_OPERATOR, line, col);
                new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                new_tokens[new_token_count++] = create_token_node("0", TOKEN_NUMBER, line, col);
                new_tokens[new_token_count++] = create_token_node(";", TOKEN_PUNCTUATION, line, col);
                new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                
                /* Add: loop_idx_var < sizeof(collection)/sizeof(collection[0]); */
                new_tokens[new_token_count++] = create_token_node(loop_idx_var, TOKEN_IDENTIFIER, line, col);
                new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                new_tokens[new_token_count++] = create_token_node("<", TOKEN_OPERATOR, line, col);
                new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                snprintf(buf, sizeof(buf), "sizeof(%s)/sizeof(%s[0])", collection_name, collection_name);
                new_tokens[new_token_count++] = create_token_node(buf, TOKEN_IDENTIFIER, line, col);
                new_tokens[new_token_count++] = create_token_node(";", TOKEN_PUNCTUATION, line, col);
                new_tokens[new_token_count++] = create_token_node(" ", TOKEN_WHITESPACE, line, col);
                
                /* Add: loop_idx_var++ */
                snprintf(buf, sizeof(buf), "%s++", loop_idx_var);
                new_tokens[new_token_count++] = create_token_node(buf, TOKEN_IDENTIFIER, line, col);
                
                /* Now mark all tokens between ( and ) for deletion */
                for (size_t i = paren_idx + 1; i < close_paren_idx; i++) {
                    if (children[i]->type == AST_TOKEN) {
                        mark_for_deletion(children[i]);
                    }
                }
                
                /* Insert all new tokens after opening paren */
                insert_nodes_after(ast, paren_idx, new_tokens, new_token_count);
                free(new_tokens);
                
                /* Update indices after insertion */
                close_paren_idx += new_token_count;
                count = ast->child_count;
                children = ast->children;
                
                /* Now find the loop body and insert the value variable declaration */
                /* The loop body starts after the closing paren */
                size_t body_start = skip_whitespace(children, count, close_paren_idx + 1);
                
                /* Check if body is a block { } or a single statement */
                if (body_start < count && children[body_start]->type == AST_TOKEN &&
                    token_equals(&children[body_start]->token, "{")) {
                    
                    /* Insert after the opening brace */
                    /* Build: val_type val = collection[loop_idx_var]; */
                    ASTNode_t **val_decl_tokens = malloc(sizeof(ASTNode_t*) * 30);
                    size_t val_decl_count = 0;
                    
                    if (!val_decl_tokens) {
                        return; /* Out of memory */
                    }
                    
                    Token *brace_tok = &children[body_start]->token;
                    
                    /* Add newline and indentation for readability */
                    val_decl_tokens[val_decl_count++] = create_token_node("\n        ", TOKEN_WHITESPACE,
                                                                          brace_tok->line, brace_tok->column);
                    
                    /* Add 'mut' keyword if the value type had it */
                    if (val_has_mut) {
                        val_decl_tokens[val_decl_count++] = create_token_node("mut", TOKEN_KEYWORD,
                                                                              brace_tok->line, brace_tok->column);
                        val_decl_tokens[val_decl_count++] = create_token_node(" ", TOKEN_WHITESPACE,
                                                                              brace_tok->line, brace_tok->column);
                    }
                    
                    /* Add the value type */
                    val_decl_tokens[val_decl_count++] = create_token_node(val_type_buf, TOKEN_IDENTIFIER,
                                                                          brace_tok->line, brace_tok->column);
                    
                    /* Add: val = collection[loop_idx_var]; */
                    val_decl_tokens[val_decl_count++] = create_token_node(" ", TOKEN_WHITESPACE,
                                                                          brace_tok->line, brace_tok->column);
                    val_decl_tokens[val_decl_count++] = create_token_node(val_var_name, TOKEN_IDENTIFIER,
                                                                          brace_tok->line, brace_tok->column);
                    val_decl_tokens[val_decl_count++] = create_token_node(" ", TOKEN_WHITESPACE,
                                                                          brace_tok->line, brace_tok->column);
                    val_decl_tokens[val_decl_count++] = create_token_node("=", TOKEN_OPERATOR,
                                                                          brace_tok->line, brace_tok->column);
                    val_decl_tokens[val_decl_count++] = create_token_node(" ", TOKEN_WHITESPACE,
                                                                          brace_tok->line, brace_tok->column);
                    snprintf(buf, sizeof(buf), "%s[%s]", collection_name, loop_idx_var);
                    val_decl_tokens[val_decl_count++] = create_token_node(buf, TOKEN_IDENTIFIER,
                                                                          brace_tok->line, brace_tok->column);
                    val_decl_tokens[val_decl_count++] = create_token_node(";", TOKEN_PUNCTUATION,
                                                                          brace_tok->line, brace_tok->column);
                    
                    /* Insert after the opening brace */
                    insert_nodes_after(ast, body_start, val_decl_tokens, val_decl_count);
                    free(val_decl_tokens);
                }
            }
        } else {
            /* Single variable: for (type var : collection) - not yet implemented */
            (void)filename;
            (void)source;
        }
    }
}

/* Main transformation function */
void transpiler_transform_foreach(ASTNode_t *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    ASTNode_t **children = ast->children;
    size_t count = ast->child_count;
    
    /* Find all for loops and check if they use foreach syntax */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type == AST_TOKEN && 
            (children[i]->token.type == TOKEN_KEYWORD || children[i]->token.type == TOKEN_IDENTIFIER) &&
            token_equals(&children[i]->token, "for")) {
            
            /* Check if this is a foreach pattern */
            size_t colon_pos = 0;
            if (is_foreach_pattern(children, count, i, &colon_pos)) {
                transform_foreach_loop(ast, i, filename, source);
                
                /* Update children and count after transformation */
                children = ast->children;
                count = ast->child_count;
            }
        }
        
        /* Recursively transform children */
        if (children[i]->child_count > 0) {
            transpiler_transform_foreach(children[i], filename, source);
        }
    }
}
