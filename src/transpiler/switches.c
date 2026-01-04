/*
 * CZar - C semantic authority layer
 * Transpiler switches module (transpiler/switches.c)
 *
 * Handles generic switch statement transformations and validation.
 */

#define _POSIX_C_SOURCE 200809L

#include "switches.h"
#include "../transpiler.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Global context for error reporting */
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

/* Validate that each case in a switch has explicit control flow */
static void validate_switch_case_control_flow_internal(ASTNode **children, size_t count, size_t switch_pos) {
    /* Find the switch body */
    size_t i = skip_whitespace(children, count, switch_pos + 1);
    
    /* Skip switch expression: ( ... ) */
    if (i >= count || children[i]->type != AST_TOKEN ||
        !token_text_equals(&children[i]->token, "(")) {
        return;
    }
    
    int paren_depth = 1;
    i++;
    while (i < count && paren_depth > 0) {
        if (children[i]->type == AST_TOKEN &&
            children[i]->token.type == TOKEN_PUNCTUATION) {
            if (token_text_equals(&children[i]->token, "(")) paren_depth++;
            else if (token_text_equals(&children[i]->token, ")")) paren_depth--;
        }
        i++;
    }
    
    i = skip_whitespace(children, count, i);
    
    /* Find opening brace */
    if (i >= count || children[i]->type != AST_TOKEN ||
        !token_text_equals(&children[i]->token, "{")) {
        return;
    }
    
    size_t switch_body_start = i;
    
    /* Find closing brace */
    int brace_depth = 1;
    i++;
    size_t switch_body_end = i;
    while (i < count && brace_depth > 0) {
        if (children[i]->type == AST_TOKEN &&
            children[i]->token.type == TOKEN_PUNCTUATION) {
            if (token_text_equals(&children[i]->token, "{")) brace_depth++;
            else if (token_text_equals(&children[i]->token, "}")) {
                brace_depth--;
                if (brace_depth == 0) switch_body_end = i;
            }
        }
        i++;
    }
    
    /* Scan for case/default labels and validate control flow */
    for (i = switch_body_start; i < switch_body_end; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;
        
        /* Look for case or default */
        if ((tok->type == TOKEN_KEYWORD || tok->type == TOKEN_IDENTIFIER) &&
            (strcmp(tok->text, "case") == 0 || strcmp(tok->text, "default") == 0)) {
            
            size_t case_start = i;
            
            /* Find the colon after case/default */
            size_t j = i + 1;
            while (j < count) {  /* Search in full AST, not just switch body */
                if (children[j]->type == AST_TOKEN &&
                    (children[j]->token.type == TOKEN_OPERATOR || children[j]->token.type == TOKEN_PUNCTUATION) &&
                    token_text_equals(&children[j]->token, ":")) {
                    break;
                }
                j++;
                if (j >= switch_body_end) break;  /* But still stop at switch end */
            }
            
            if (j >= switch_body_end || j >= count) {
                continue;
            }
            
            /* Now scan from after the colon to the next case/default/closing brace */
            j = skip_whitespace(children, count, j + 1);
            size_t case_body_start = j;
            size_t case_body_end = switch_body_end;
            
            /* Find the end of this case (next case/default or closing brace) */
            int inner_brace_depth = 0;
            while (j < switch_body_end) {
                if (children[j]->type != AST_TOKEN) {
                    j++;
                    continue;
                }
                
                Token *t = &children[j]->token;
                
                /* Track braces to avoid false positives in nested blocks */
                if (t->type == TOKEN_PUNCTUATION) {
                    if (token_text_equals(t, "{")) inner_brace_depth++;
                    else if (token_text_equals(t, "}")) {
                        if (inner_brace_depth > 0) inner_brace_depth--;
                        else {
                            case_body_end = j;
                            break;
                        }
                    }
                }
                
                /* Check for next case/default at same nesting level */
                if (inner_brace_depth == 0 &&
                    (t->type == TOKEN_KEYWORD || t->type == TOKEN_IDENTIFIER) &&
                    (strcmp(t->text, "case") == 0 || strcmp(t->text, "default") == 0)) {
                    case_body_end = j;
                    break;
                }
                
                j++;
            }
            
            /* Now validate that the case body has explicit control flow */
            int has_control_flow = 0;
            for (j = case_body_start; j < case_body_end; j++) {
                if (children[j]->type != AST_TOKEN) continue;
                Token *t = &children[j]->token;
                
                /* Check for control flow keywords */
                if ((t->type == TOKEN_KEYWORD || t->type == TOKEN_IDENTIFIER) &&
                    (strcmp(t->text, "break") == 0 ||
                     strcmp(t->text, "continue") == 0 ||
                     strcmp(t->text, "return") == 0 ||
                     strcmp(t->text, "goto") == 0 ||
                     strcmp(t->text, "UNREACHABLE") == 0 ||
                     strcmp(t->text, "TODO") == 0 ||
                     strcmp(t->text, "FIXME") == 0)) {
                    has_control_flow = 1;
                    break;
                }
            }
            
            /* Report error if no control flow found */
            if (!has_control_flow && case_body_end > case_body_start) {
                /* Skip empty cases (allowed to fall through to next case) */
                int is_empty = 1;
                int non_whitespace_count = 0;
                for (j = case_body_start; j < case_body_end; j++) {
                    if (children[j]->type == AST_TOKEN) {
                        Token *t = &children[j]->token;
                        /* Consider only meaningful tokens */
                        if (t->type != TOKEN_WHITESPACE && t->type != TOKEN_COMMENT &&
                            !(t->type == TOKEN_PUNCTUATION && (token_text_equals(t, ";") || 
                                                                token_text_equals(t, "{") ||
                                                                token_text_equals(t, "}")))) {
                            is_empty = 0;
                            non_whitespace_count++;
                        }
                    }
                }
                
                if (!is_empty && non_whitespace_count > 0) {
                    char error_msg[512];
                    snprintf(error_msg, sizeof(error_msg),
                             ERR_SWITCH_CASE_NO_CONTROL_FLOW);
                    cz_error(g_filename, g_source, children[case_start]->token.line, error_msg);
                }
            }
            
            /* Skip to the end of this case to continue scanning */
            i = case_body_end > 0 ? case_body_end - 1 : i;
        }
    }
}

/* Validate switch case control flow */
void transpiler_validate_switch_case_control_flow(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    g_filename = filename;
    g_source = source;
    
    ASTNode **children = ast->children;
    size_t count = ast->child_count;
    
    /* Scan for switch statements */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;
        
        /* Look for switch keyword */
        if ((tok->type == TOKEN_KEYWORD || tok->type == TOKEN_IDENTIFIER) &&
            strcmp(tok->text, "switch") == 0) {
            validate_switch_case_control_flow_internal(children, count, i);
        }
    }
}

/* Transform continue in switch cases to fallthrough */
void transpiler_transform_switch_continue_to_fallthrough(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    /* Track if we're inside a switch (not inside a loop) */
    int switch_depth = 0;
    int loop_depth = 0;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *token = &children[i]->token;

        /* Track switch/loop depth */
        if ((token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER)) {
            if (strcmp(token->text, "switch") == 0) {
                switch_depth++;
            } else if (strcmp(token->text, "for") == 0 ||
                       strcmp(token->text, "while") == 0 ||
                       strcmp(token->text, "do") == 0) {
                loop_depth++;
            } else if (strcmp(token->text, "continue") == 0) {
                /* Only transform if we're in a switch but not in a loop */
                if (switch_depth > 0 && loop_depth == 0) {
                    /* Replace continue with __attribute__((fallthrough)) or comment */
                    free(token->text);
                    #ifdef __GNUC__
                    token->text = strdup("__attribute__((fallthrough))");
                    #else
                    token->text = strdup("/* fallthrough */");
                    #endif
                    if (token->text) {
                        token->length = strlen(token->text);
                        token->type = TOKEN_COMMENT;
                    }
                }
            }
        }

        /* Track closing braces to decrement depth */
        if (token->type == TOKEN_PUNCTUATION && token_text_equals(token, "}")) {
            /* Heuristic: decrement switch/loop depth (this is simplified) */
            if (loop_depth > 0) loop_depth--;
            else if (switch_depth > 0) switch_depth--;
        }
    }
}

/* Helper to create a new AST token node */
static ASTNode *create_token_node(TokenType type, const char *text, int line, int column) {
    ASTNode *node = malloc(sizeof(ASTNode));
    if (!node) return NULL;
    
    node->type = AST_TOKEN;
    node->token.type = type;
    node->token.text = strdup(text);
    if (!node->token.text) {
        free(node);
        return NULL;
    }
    node->token.length = strlen(text);
    node->token.line = line;
    node->token.column = column;
    node->children = NULL;
    node->child_count = 0;
    node->child_capacity = 0;
    
    return node;
}

/* Helper to insert a child at a specific position in an AST node */
static int ast_insert_child(ASTNode *parent, size_t position, ASTNode *child) {
    if (!parent || !child || position > parent->child_count) {
        return 0;
    }
    
    /* Grow children array if needed */
    if (parent->child_count >= parent->child_capacity) {
        size_t new_capacity = parent->child_capacity == 0 ? 8 : parent->child_capacity * 2;
        ASTNode **new_children = realloc(parent->children, new_capacity * sizeof(ASTNode *));
        if (!new_children) {
            return 0;
        }
        parent->children = new_children;
        parent->child_capacity = new_capacity;
    }
    
    /* Shift elements to make room */
    for (size_t i = parent->child_count; i > position; i--) {
        parent->children[i] = parent->children[i - 1];
    }
    
    parent->children[position] = child;
    parent->child_count++;
    return 1;
}

/* Find the function name containing this position */
static const char *find_function_name(ASTNode **children, size_t count, size_t current_pos) {
    int brace_depth = 0;
    const char *function_name = NULL;
    const char *last_function_name = NULL;
    
    /* Scan from start to find which function we're in at current_pos */
    for (size_t i = 0; i < current_pos && i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        
        Token *tok = &children[i]->token;
        
        if (tok->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(tok, "{")) {
                brace_depth++;
                /* Check if this is a function opening brace */
                /* Look back for function name pattern: identifier ( ... ) { */
                /* Skip back over whitespace and find identifier before ( */
                for (int j = (int)i - 1; j >= 0 && j >= (int)i - 30; j--) {
                    if (children[j]->type != AST_TOKEN) continue;
                    Token *jtok = &children[j]->token;
                    
                    if (jtok->type == TOKEN_WHITESPACE || jtok->type == TOKEN_COMMENT) continue;
                    
                    /* Look for closing paren ) */
                    if (jtok->type == TOKEN_PUNCTUATION && token_text_equals(jtok, ")")) {
                        /* Found ), now look back for identifier before matching ( */
                        int paren_depth_local = 1;
                        int found_func = 0;
                        for (int k = j - 1; k >= 0 && k >= j - 30; k--) {
                            if (children[k]->type != AST_TOKEN) continue;
                            Token *ktok = &children[k]->token;
                            
                            if (ktok->type == TOKEN_PUNCTUATION) {
                                if (token_text_equals(ktok, ")")) paren_depth_local++;
                                else if (token_text_equals(ktok, "(")) {
                                    paren_depth_local--;
                                    if (paren_depth_local == 0) {
                                        /* Found matching (, look for identifier before it */
                                        for (int m = k - 1; m >= 0 && m >= k - 5; m--) {
                                            if (children[m]->type != AST_TOKEN) continue;
                                            Token *mtok = &children[m]->token;
                                            if (mtok->type == TOKEN_WHITESPACE || mtok->type == TOKEN_COMMENT) continue;
                                            if (mtok->type == TOKEN_IDENTIFIER) {
                                                /* Avoid keywords */
                                                if (strcmp(mtok->text, "if") != 0 &&
                                                    strcmp(mtok->text, "while") != 0 &&
                                                    strcmp(mtok->text, "for") != 0 &&
                                                    strcmp(mtok->text, "switch") != 0) {
                                                    last_function_name = mtok->text;
                                                    found_func = 1;
                                                }
                                                break;
                                            }
                                            break; /* Not an identifier */
                                        }
                                        break; /* Found matching ( */
                                    }
                                }
                            }
                        }
                        if (found_func) break;
                    }
                    break; /* First non-whitespace token after { wasn't ) */
                }
                /* If we just entered the first brace level, this is the function */
                if (brace_depth == 1 && last_function_name) {
                    function_name = last_function_name;
                }
            } else if (token_text_equals(tok, "}")) {
                brace_depth--;
                /* If we exit all braces, clear function name */
                if (brace_depth == 0) {
                    function_name = NULL;
                }
            }
        }
    }
    
    return function_name;
}

/* Insert default cases into switches that lack them */
void transpiler_insert_switch_default_cases(ASTNode *ast, const char *filename) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *token = &children[i]->token;

        /* Look for "switch" keyword */
        if ((token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER) &&
            strcmp(token->text, "switch") == 0) {
            
            /* Find the switch expression */
            size_t j = skip_whitespace(children, count, i + 1);
            
            if (j >= count || children[j]->type != AST_TOKEN ||
                !token_text_equals(&children[j]->token, "(")) {
                continue;
            }
            
            /* Find closing paren and opening brace */
            int paren_depth = 1;
            j++;
            while (j < count && paren_depth > 0) {
                if (children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_PUNCTUATION) {
                    if (token_text_equals(&children[j]->token, "(")) paren_depth++;
                    else if (token_text_equals(&children[j]->token, ")")) paren_depth--;
                }
                j++;
            }
            
            j = skip_whitespace(children, count, j);
            
            /* Find switch body braces */
            if (j >= count || children[j]->type != AST_TOKEN ||
                !token_text_equals(&children[j]->token, "{")) {
                continue;
            }
            
            size_t switch_body_start = j;
            
            /* Find closing brace */
            int brace_depth = 1;
            j++;
            size_t switch_body_end = j;
            while (j < count && brace_depth > 0) {
                if (children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_PUNCTUATION) {
                    if (token_text_equals(&children[j]->token, "{")) brace_depth++;
                    else if (token_text_equals(&children[j]->token, "}")) {
                        brace_depth--;
                        if (brace_depth == 0) {
                            switch_body_end = j;
                        }
                    }
                }
                j++;
            }
            
            /* Check if there's a default */
            int has_default = 0;
            
            for (size_t k = switch_body_start; k < switch_body_end; k++) {
                if (children[k]->type != AST_TOKEN) continue;
                Token *tok = &children[k]->token;
                
                /* Check for default */
                if ((tok->type == TOKEN_KEYWORD || tok->type == TOKEN_IDENTIFIER) &&
                    strcmp(tok->text, "default") == 0) {
                    has_default = 1;
                    break;
                }
            }
            
            /* If no default, insert one */
            if (!has_default) {
                int line = children[switch_body_end]->token.line;
                /* Find function name at the switch statement location */
                const char *func_name = find_function_name(children, count, switch_body_start);
                if (!func_name) func_name = "<unknown>";
                
                /* Insert: default: { fprintf(stderr, "file:line: func: Unreachable code reached: \n"); abort(); } */
                /* Build nodes in forward order */
                ASTNode *nodes[20];
                int node_count = 0;
                
                nodes[node_count++] = create_token_node(TOKEN_WHITESPACE, "\n    ", line, 0);
                nodes[node_count++] = create_token_node(TOKEN_KEYWORD, "default", line, 0);
                nodes[node_count++] = create_token_node(TOKEN_PUNCTUATION, ":", line, 0);
                nodes[node_count++] = create_token_node(TOKEN_WHITESPACE, " ", line, 0);
                
                /* Create inline expansion: { fprintf(stderr, "...\n"); abort(); } */
                char inline_code[512];
                snprintf(inline_code, sizeof(inline_code),
                         "{ fprintf(stderr, \"%s:%d: %s: Unreachable code reached: \\n\"); abort(); }",
                         filename ? filename : "<unknown>", line, func_name);
                
                nodes[node_count++] = create_token_node(TOKEN_PUNCTUATION, inline_code, line, 0);
                nodes[node_count++] = create_token_node(TOKEN_WHITESPACE, "\n    ", line, 0);
                
                /* Insert all nodes in reverse order before the closing brace */
                for (int n = node_count - 1; n >= 0; n--) {
                    if (nodes[n] && !ast_insert_child(ast, switch_body_end, nodes[n])) {
                        /* Failed to insert, free the node */
                        free(nodes[n]->token.text);
                        free(nodes[n]);
                    }
                }
            }
        }
    }
}
