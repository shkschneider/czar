/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Transforms mutability keywords for C compilation.
 * Strategy: mut = opposite of const. Strip mut, add const for non-mut.
 * Let the C compiler do the heavy checking.
 */

#define _POSIX_C_SOURCE 200809L

#include "mutability.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

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
static int is_in_function_params(ASTNode **children, size_t idx) {
    /* Look backward for opening ( */
    int paren_count = 0;
    for (int i = (int)idx - 1; i >= 0 && i >= (int)idx - 30; i--) {
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
                    /* Found opening paren, check if it's a function declaration */
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

/* Check if this is a variable declaration context (not in function parameters, not in struct fields) */
static int is_variable_declaration(ASTNode **children, size_t count, size_t type_idx) {
    /* Check if we're inside a struct definition (look backward for struct keyword + opening brace) */
    int in_struct = 0;
    int brace_count = 0;
    for (int k = (int)type_idx - 1; k >= 0 && k >= (int)type_idx - 50; k--) {
        if (children[k]->type == AST_TOKEN) {
            const char *ktext = children[k]->token.text;
            if (strcmp(ktext, "}") == 0) {
                brace_count++;
            } else if (strcmp(ktext, "{") == 0) {
                brace_count--;
                if (brace_count < 0) {
                    /* Found opening brace, check if it's part of struct definition */
                    for (int m = k - 1; m >= 0 && m >= k - 10; m--) {
                        if (children[m]->type == AST_TOKEN) {
                            if (children[m]->token.type == TOKEN_WHITESPACE ||
                                children[m]->token.type == TOKEN_COMMENT) {
                                continue;
                            }
                            if (children[m]->token.type == TOKEN_KEYWORD &&
                                strcmp(children[m]->token.text, "struct") == 0) {
                                in_struct = 1;
                            }
                            break;
                        }
                    }
                    break;
                }
            }
        }
    }
    
    /* If inside struct definition, this is a field, not a variable */
    if (in_struct) {
        return 0;
    }
    
    /* Must have identifier after type */
    size_t next_idx = skip_ws(children, count, type_idx + 1);
    
    /* Skip optional pointer */
    if (next_idx < count && children[next_idx]->type == AST_TOKEN &&
        strcmp(children[next_idx]->token.text, "*") == 0) {
        next_idx = skip_ws(children, count, next_idx + 1);
    }
    
    /* Check if next token is an identifier (variable name) */
    if (next_idx >= count || children[next_idx]->type != AST_TOKEN ||
        children[next_idx]->token.type != TOKEN_IDENTIFIER) {
        return 0;
    }
    
    /* Check what follows the identifier */
    size_t after_id = skip_ws(children, count, next_idx + 1);
    if (after_id >= count || children[after_id]->type != AST_TOKEN) {
        return 0;
    }
    
    const char *after_text = children[after_id]->token.text;
    
    /* Variable declarations typically have = or ; after the identifier */
    /* Also check for [ for array declarations */
    if (strcmp(after_text, "=") == 0 || 
        strcmp(after_text, ";") == 0 ||
        strcmp(after_text, "[") == 0 ||
        strcmp(after_text, ",") == 0) {  /* Multiple declarations */
        return 1;
    }
    
    return 0;
}

/* Check if next non-whitespace token is a pointer (*) */
static int is_followed_by_pointer(ASTNode **children, size_t count, size_t type_idx) {
    size_t next_idx = skip_ws(children, count, type_idx + 1);
    if (next_idx >= count || children[next_idx]->type != AST_TOKEN) return 0;
    return strcmp(children[next_idx]->token.text, "*") == 0;
}

/* Structure to track function parameters and their mutability */
typedef struct {
    char **param_names;
    int *param_is_mutable;  /* 1 if mut, 0 if immutable */
    int *param_is_pointer;  /* 1 if pointer type */
    size_t count;
    size_t capacity;
} ParamTracker;

static ParamTracker *tracker = NULL;

/* Initialize parameter tracker */
static void init_param_tracker(void) {
    if (!tracker) {
        tracker = malloc(sizeof(ParamTracker));
        if (tracker) {
            tracker->param_names = NULL;
            tracker->param_is_mutable = NULL;
            tracker->param_is_pointer = NULL;
            tracker->count = 0;
            tracker->capacity = 0;
        }
    }
}

/* Clear parameter tracker */
static void clear_param_tracker(void) {
    if (tracker) {
        for (size_t i = 0; i < tracker->count; i++) {
            free(tracker->param_names[i]);
        }
        free(tracker->param_names);
        free(tracker->param_is_mutable);
        free(tracker->param_is_pointer);
        tracker->count = 0;
    }
}

/* Free parameter tracker */
static void free_param_tracker(void) {
    if (tracker) {
        clear_param_tracker();
        free(tracker);
        tracker = NULL;
    }
}

/* Add a parameter to tracker */
static void add_param(const char *name, int is_mutable, int is_pointer) {
    if (!tracker) return;
    
    /* Ensure capacity */
    if (tracker->count >= tracker->capacity) {
        size_t new_cap = (tracker->capacity == 0) ? 8 : tracker->capacity * 2;
        char **new_names = realloc(tracker->param_names, new_cap * sizeof(char *));
        int *new_mut = realloc(tracker->param_is_mutable, new_cap * sizeof(int));
        int *new_ptr = realloc(tracker->param_is_pointer, new_cap * sizeof(int));
        
        if (!new_names || !new_mut || !new_ptr) {
            free(new_names);
            free(new_mut);
            free(new_ptr);
            return;
        }
        
        tracker->param_names = new_names;
        tracker->param_is_mutable = new_mut;
        tracker->param_is_pointer = new_ptr;
        tracker->capacity = new_cap;
    }
    
    tracker->param_names[tracker->count] = strdup(name);
    tracker->param_is_mutable[tracker->count] = is_mutable;
    tracker->param_is_pointer[tracker->count] = is_pointer;
    tracker->count++;
}

/* Check if a parameter is immutable */
static int is_immutable_param(const char *name, int *is_pointer) {
    if (!tracker) return 0;
    
    for (size_t i = 0; i < tracker->count; i++) {
        if (strcmp(tracker->param_names[i], name) == 0) {
            if (is_pointer) {
                *is_pointer = tracker->param_is_pointer[i];
            }
            return !tracker->param_is_mutable[i];
        }
    }
    return 0;
}

/* Scan and track function parameters */
static void scan_function_params(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) return;
    
    clear_param_tracker();
    
    /* Look for function definitions and track their parameters */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        
        Token *token = &ast->children[i]->token;
        
        /* Look for patterns like: type identifier ( params ) { */
        /* This is simplified - looks for ( after identifier, then scans params until ) */
        if (token->type == TOKEN_IDENTIFIER || token->type == TOKEN_KEYWORD) {
            /* Check if this might be a function name by looking for ( after it */
            size_t paren_idx = skip_ws(ast->children, ast->child_count, i + 1);
            if (paren_idx < ast->child_count &&
                ast->children[paren_idx]->type == AST_TOKEN &&
                strcmp(ast->children[paren_idx]->token.text, "(") == 0) {
                
                /* Found function, scan parameters */
                size_t param_start = paren_idx + 1;
                int paren_depth = 1;
                int has_mut = 0;
                int is_pointer = 0;
                char *param_name = NULL;
                
                for (size_t j = param_start; j < ast->child_count && paren_depth > 0; j++) {
                    if (ast->children[j]->type != AST_TOKEN) continue;
                    
                    Token *pt = &ast->children[j]->token;
                    
                    if (strcmp(pt->text, "(") == 0) {
                        paren_depth++;
                    } else if (strcmp(pt->text, ")") == 0) {
                        paren_depth--;
                        if (paren_depth == 0 && param_name) {
                            add_param(param_name, has_mut, is_pointer);
                        }
                    } else if (strcmp(pt->text, ",") == 0) {
                        if (param_name) {
                            add_param(param_name, has_mut, is_pointer);
                            param_name = NULL;
                            has_mut = 0;
                            is_pointer = 0;
                        }
                    } else if (pt->type == TOKEN_IDENTIFIER && strcmp(pt->text, "mut") == 0) {
                        has_mut = 1;
                    } else if (strcmp(pt->text, "*") == 0) {
                        is_pointer = 1;
                    } else if (pt->type == TOKEN_IDENTIFIER &&
                              strcmp(pt->text, "mut") != 0 &&
                              strcmp(pt->text, "const") != 0) {
                        /* This could be a type or parameter name */
                        /* Simple heuristic: if we've seen a type already, this is the param name */
                        size_t prev_idx = j;
                        if (prev_idx > param_start + 1) {
                            /* Not the first token, likely a param name */
                            param_name = pt->text;
                        }
                    }
                }
            }
        }
    }
}

/* Validate no modifications to immutable parameters in function bodies */
static void validate_no_immutable_modifications(ASTNode *ast, const char *filename, const char *source) {
    if (!ast) return;
    
    /* Look for assignment patterns */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        
        Token *token = &ast->children[i]->token;
        
        /* Look for = assignments (but not == comparisons or other compound assignments) */
        if (strcmp(token->text, "=") == 0) {
            /* Check what's being assigned to */
            /* Look backward for the target of assignment */
            for (int j = (int)i - 1; j >= 0 && j >= (int)i - 10; j--) {
                if (ast->children[j]->type != AST_TOKEN) continue;
                if (ast->children[j]->token.type == TOKEN_WHITESPACE ||
                    ast->children[j]->token.type == TOKEN_COMMENT) continue;
                
                Token *target = &ast->children[j]->token;
                
                /* Check for patterns:
                 * 1. *identifier = ... (dereferencing pointer parameter) 
                 * 2. identifier->field = ... (accessing through pointer)
                 * Note: We DON'T check "identifier =" as reassigning a pointer-to-const is valid in C
                 */
                
                /* Pattern 2: identifier->field = */
                if (strcmp(target->text, "->") == 0 || strcmp(target->text, ".") == 0) {
                    /* Find the identifier before -> or . */
                    for (int k = j - 1; k >= 0 && k >= j - 5; k--) {
                        if (ast->children[k]->type != AST_TOKEN) continue;
                        if (ast->children[k]->token.type == TOKEN_WHITESPACE ||
                            ast->children[k]->token.type == TOKEN_COMMENT) continue;
                        
                        if (ast->children[k]->token.type == TOKEN_IDENTIFIER) {
                            int is_ptr = 0;
                            if (is_immutable_param(ast->children[k]->token.text, &is_ptr) && is_ptr) {
                                char error_msg[512];
                                snprintf(error_msg, sizeof(error_msg),
                                        "Cannot modify through immutable pointer parameter '%s'. "
                                        "Parameters without 'mut' are const and cannot be used to modify data.",
                                        ast->children[k]->token.text);
                                cz_error(filename, source, token->line, error_msg);
                            }
                        }
                        break;
                    }
                    break;
                }
                
                /* Pattern 1: *identifier = */
                if (strcmp(target->text, "*") == 0) {
                    /* Find the identifier after * */
                    size_t id_idx = skip_ws(ast->children, ast->child_count, j + 1);
                    if (id_idx < ast->child_count &&
                        ast->children[id_idx]->type == AST_TOKEN &&
                        ast->children[id_idx]->token.type == TOKEN_IDENTIFIER) {
                        
                        int is_ptr = 0;
                        if (is_immutable_param(ast->children[id_idx]->token.text, &is_ptr) && is_ptr) {
                            char error_msg[512];
                            snprintf(error_msg, sizeof(error_msg),
                                    "Cannot modify through immutable pointer parameter '%s'. "
                                    "Parameters without 'mut' are const and cannot be used to modify data.",
                                    ast->children[id_idx]->token.text);
                            cz_error(filename, source, token->line, error_msg);
                        }
                    }
                    break;
                }
                
                /* Stop at statement boundaries */
                if (strcmp(target->text, ";") == 0 || strcmp(target->text, "{") == 0 ||
                    strcmp(target->text, "}") == 0) {
                    break;
                }
                
                break; /* Process only the immediate left side of = */
            }
        }
    }
    
    /* Recursively validate children */
    for (size_t i = 0; i < ast->child_count; i++) {
        validate_no_immutable_modifications(ast->children[i], filename, source);
    }
}

/* Validate mutability rules - mut parameters must be pointers and immutable params cannot modify data */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) return;
    
    /* Initialize parameter tracker */
    init_param_tracker();
    
    /* Scan function parameters to track mutability */
    scan_function_params(ast);
    
    /* Look for 'mut' keywords in function parameters */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type == AST_TOKEN) {
            Token *token = &ast->children[i]->token;
            
            /* Look for 'mut' keyword in function parameter context */
            if (token->type == TOKEN_IDENTIFIER &&
                strcmp(token->text, "mut") == 0 &&
                is_in_function_params(ast->children, i)) {
                
                /* Check if followed by a type */
                size_t type_idx = skip_ws(ast->children, ast->child_count, i + 1);
                if (type_idx >= ast->child_count || ast->children[type_idx]->type != AST_TOKEN) continue;
                
                /* Check if the type is followed by a pointer (*) */
                if (!is_followed_by_pointer(ast->children, ast->child_count, type_idx)) {
                    /* mut parameter is not a pointer - ERROR */
                    char error_msg[256];
                    snprintf(error_msg, sizeof(error_msg),
                            "mut parameters must be pointers. Use 'mut Type* param' not 'mut Type param'");
                    cz_error(filename, source, token->line, error_msg);
                }
            }
        }
    }
    
    /* Validate no modifications through immutable pointer parameters */
    validate_no_immutable_modifications(ast, filename, source);
    
    /* Clean up parameter tracker */
    free_param_tracker();
}

/* Check if we're looking at the start of a parameter (after opening paren or comma) */
static int is_param_start(ASTNode **children, size_t idx) {
    /* Look backward for ( or , */
    for (int i = (int)idx - 1; i >= 0 && i >= (int)idx - 10; i--) {
        if (children[i]->type == AST_TOKEN) {
            if (children[i]->token.type == TOKEN_WHITESPACE ||
                children[i]->token.type == TOKEN_COMMENT) {
                continue;
            }
            const char *text = children[i]->token.text;
            if (strcmp(text, "(") == 0 || strcmp(text, ",") == 0) {
                return 1;
            }
            /* If we find something else first, it's not param start */
            return 0;
        }
    }
    return 0;
}

/* Helper function to create a new token node */
static ASTNode *create_token_node(TokenType type, const char *text, int line) {
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
    node->token.column = 0;
    node->children = NULL;
    node->child_count = 0;
    node->child_capacity = 0;
    
    return node;
}

/* Insert a node into the AST at the specified position */
static int insert_node_at(ASTNode *ast, size_t position, ASTNode *node) {
    /* Ensure capacity */
    if (ast->child_count + 1 > ast->child_capacity) {
        size_t new_capacity = (ast->child_capacity == 0) ? 16 : ast->child_capacity * 2;
        ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
        if (!new_children) {
            return 0; /* Allocation failed */
        }
        ast->children = new_children;
        ast->child_capacity = new_capacity;
    }
    
    /* Shift elements to make room */
    for (size_t i = ast->child_count; i > position; i--) {
        ast->children[i] = ast->children[i - 1];
    }
    
    /* Insert the node */
    ast->children[position] = node;
    ast->child_count++;
    
    return 1;
}

/* Transform mutability keywords */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) return;

    if (ast->type == AST_TRANSLATION_UNIT) {
        /* Two-pass transformation:
         * Pass 1: Add 'const' for variables/parameters without 'mut' 
         * Pass 2: Strip 'mut' keyword 
         * This ordering ensures we can detect mut correctly before stripping it
         */
        
        /* PASS 1: Add const for non-mut variables/parameters */
        for (size_t i = 0; i < ast->child_count; i++) {
            if (ast->children[i]->type == AST_TOKEN) {
                Token *token = &ast->children[i]->token;
                
                /* Look for type keywords (without preceding 'mut') in:
                 * - Function parameters
                 * - Local variable declarations
                 * - Struct instances
                 * BUT NOT in struct field definitions
                 */
                if ((token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER)) {
                    int in_params = is_in_function_params(ast->children, i);
                    int in_var_decl = is_variable_declaration(ast->children, ast->child_count, i);
                    
                    /* Skip if neither in params nor in var decl */
                    if (!in_params && !in_var_decl) {
                        continue;
                    }
                    
                    /* Only process if in function parameters OR in variable declaration */
                    if ((in_params && is_param_start(ast->children, i)) || in_var_decl) {
                        /* Check if this looks like a type (common types or identifiers that could be typedefs) */
                        /* EXCLUDE void - it cannot be qualified with const */
                        const char *text = token->text;
                        int is_type = (strcmp(text, "int") == 0 ||
                                      strcmp(text, "char") == 0 ||
                                      strcmp(text, "float") == 0 ||
                                      strcmp(text, "double") == 0 ||
                                      strncmp(text, "u", 1) == 0 ||  /* u8, u16, u32, u64 */
                                      strncmp(text, "i", 1) == 0 ||  /* i8, i16, i32, i64 */
                                      strcmp(text, "bool") == 0 ||
                                      strcmp(text, "size_t") == 0 ||
                                      /* Also check for common identifier patterns (struct typedefs) */
                                      (token->type == TOKEN_IDENTIFIER && isupper(text[0])));
                        
                        if (is_type) {
                            /* Check if NOT preceded by 'mut' or 'const' (look back, skipping whitespace) */
                            int has_mut = 0;
                            int has_const = 0;
                            int has_struct = 0;
                            for (int j = (int)i - 1; j >= 0 && j >= (int)i - 5; j--) {
                                if (ast->children[j]->type == AST_TOKEN) {
                                    if (ast->children[j]->token.type == TOKEN_WHITESPACE ||
                                        ast->children[j]->token.type == TOKEN_COMMENT) {
                                        continue;
                                    }
                                    if (ast->children[j]->token.type == TOKEN_IDENTIFIER &&
                                        strcmp(ast->children[j]->token.text, "mut") == 0) {
                                        has_mut = 1;
                                    }
                                    if (ast->children[j]->token.type == TOKEN_KEYWORD &&
                                        strcmp(ast->children[j]->token.text, "const") == 0) {
                                        has_const = 1;
                                    }
                                    if (ast->children[j]->token.type == TOKEN_KEYWORD &&
                                        strcmp(ast->children[j]->token.text, "struct") == 0) {
                                        has_struct = 1;
                                    }
                                    break;
                                }
                            }
                            
                            /* Check if this type ends with _t (typedef convention) */
                            size_t text_len = strlen(text);
                            int is_typedef = (text_len >= 2 && strcmp(text + text_len - 2, "_t") == 0);
                            
                            /* If uppercase but not a _t typedef, skip const addition 
                             * (likely a bare struct name like Point, not Point_t) */
                            if (token->type == TOKEN_IDENTIFIER && isupper(text[0]) && !is_typedef) {
                                /* Skip - don't add const to bare struct names */
                                continue;
                            }
                            
                            /* If no 'mut' and no 'const' and no 'struct', insert a 'const' token before the type */
                            if (!has_mut && !has_const && !has_struct) {
                                ASTNode *const_node = create_token_node(TOKEN_KEYWORD, "const", token->line);
                                ASTNode *space_node = create_token_node(TOKEN_WHITESPACE, " ", token->line);
                                
                                if (const_node && space_node) {
                                    /* Insert const and space before the current position */
                                    if (insert_node_at(ast, i, const_node) &&
                                        insert_node_at(ast, i + 1, space_node)) {
                                        /* Adjust loop counter since we inserted 2 nodes */
                                        i += 2;
                                    } else {
                                        /* Failed to insert, clean up */
                                        if (const_node) {
                                            if (const_node->token.text) free(const_node->token.text);
                                            free(const_node);
                                        }
                                        if (space_node) {
                                            if (space_node->token.text) free(space_node->token.text);
                                            free(space_node);
                                        }
                                    }
                                } else {
                                    /* Failed to create nodes, clean up */
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
                        }
                    }
                }
            }
        }
        
        /* PASS 1.5: Add const after * for non-mut pointers to make pointer itself const */
        for (size_t i = 0; i < ast->child_count; i++) {
            if (ast->children[i]->type == AST_TOKEN) {
                Token *token = &ast->children[i]->token;
                
                /* Look for * (pointer) tokens */
                if (strcmp(token->text, "*") == 0) {
                    /* Check if preceded by mut anywhere in this declaration (look back for mut, stopping at ; or { or }) */
                    int has_mut_in_decl = 0;
                    for (int j = (int)i - 1; j >= 0 && j >= (int)i - 20; j--) {
                        if (ast->children[j]->type == AST_TOKEN) {
                            const char *jtext = ast->children[j]->token.text;
                            
                            /* Stop at statement/block boundaries */
                            if (strcmp(jtext, ";") == 0 || strcmp(jtext, "{") == 0 || 
                                strcmp(jtext, "}") == 0 || strcmp(jtext, ")") == 0 ||
                                strcmp(jtext, ",") == 0) {
                                break;
                            }
                            
                            if (ast->children[j]->token.type == TOKEN_WHITESPACE ||
                                ast->children[j]->token.type == TOKEN_COMMENT) {
                                continue;
                            }
                            if (ast->children[j]->token.type == TOKEN_IDENTIFIER &&
                                strcmp(jtext, "mut") == 0) {
                                has_mut_in_decl = 1;
                                break;
                            }
                        }
                    }
                    
                    /* If no mut in this declaration, check if const already after */
                    if (!has_mut_in_decl) {
                        size_t next_idx = skip_ws(ast->children, ast->child_count, i + 1);
                        int has_const_after = 0;
                        if (next_idx < ast->child_count && ast->children[next_idx]->type == AST_TOKEN &&
                            ast->children[next_idx]->token.type == TOKEN_KEYWORD &&
                            strcmp(ast->children[next_idx]->token.text, "const") == 0) {
                            has_const_after = 1;
                        }
                        
                        /* If no const after, add it to make pointer itself const */
                        if (!has_const_after) {
                            ASTNode *space_node = create_token_node(TOKEN_WHITESPACE, " ", token->line);
                            ASTNode *const_node = create_token_node(TOKEN_KEYWORD, "const", token->line);
                            
                            if (space_node && const_node) {
                                /* Insert space and const after the * */
                                if (insert_node_at(ast, i + 1, space_node) &&
                                    insert_node_at(ast, i + 2, const_node)) {
                                    /* Adjust loop counter since we inserted 2 nodes */
                                    i += 2;
                                } else {
                                    /* Failed to insert, clean up */
                                    if (space_node) {
                                        if (space_node->token.text) free(space_node->token.text);
                                        free(space_node);
                                    }
                                    if (const_node) {
                                        if (const_node->token.text) free(const_node->token.text);
                                        free(const_node);
                                    }
                                }
                            } else {
                                /* Failed to create nodes, clean up */
                                if (space_node) {
                                    if (space_node->token.text) free(space_node->token.text);
                                    free(space_node);
                                }
                                if (const_node) {
                                    if (const_node->token.text) free(const_node->token.text);
                                    free(const_node);
                                }
                            }
                        }
                    }
                }
            }
        }
        
        /* PASS 2: Strip 'mut' keyword */
        for (size_t i = 0; i < ast->child_count; i++) {
            if (ast->children[i]->type == AST_TOKEN) {
                Token *token = &ast->children[i]->token;
                
                /* Look for 'mut' keyword */
                if (token->type == TOKEN_IDENTIFIER &&
                    strcmp(token->text, "mut") == 0) {
                    
                    /* Remove 'mut' keyword */
                    free(token->text);
                    token->text = strdup("");
                    if (!token->text) {
                        fprintf(stderr, "[CZAR] Warning: Failed to allocate memory for empty string\n");
                        token->text = malloc(1);
                        if (token->text) {
                            token->text[0] = '\0';
                        }
                    }
                    token->length = 0;
                    
                    /* Also remove following whitespace */
                    if (i + 1 < ast->child_count &&
                        ast->children[i + 1]->type == AST_TOKEN &&
                        ast->children[i + 1]->token.type == TOKEN_WHITESPACE) {
                        Token *ws_token = &ast->children[i + 1]->token;
                        free(ws_token->text);
                        ws_token->text = strdup("");
                        if (!ws_token->text) {
                            fprintf(stderr, "[CZAR] Warning: Failed to allocate memory for empty string\n");
                            ws_token->text = malloc(1);
                            if (ws_token->text) {
                                ws_token->text[0] = '\0';
                            }
                        }
                        ws_token->length = 0;
                    }
                }
            }
        }
    }

    /* Recursively transform children */
    for (size_t i = 0; i < ast->child_count; i++) {
        transpiler_transform_mutability(ast->children[i]);
    }
}
