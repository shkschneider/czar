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

/* Check if we're inside a struct definition */
static int is_inside_struct_definition(ASTNode **children, size_t count, size_t idx) {
    int brace_depth = 0;
    
    /* Scan backward to find if we're inside braces that follow 'struct' */
    for (int i = (int)idx - 1; i >= 0; i--) {
        if (children[i]->type != AST_TOKEN) continue;
        
        const char *text = children[i]->token.text;
        
        /* Track brace depth (going backward, so reversed) */
        if (strcmp(text, "}") == 0) {
            brace_depth++;
        } else if (strcmp(text, "{") == 0) {
            brace_depth--;
            
            /* If we just exited braces, check what's before the { */
            if (brace_depth < 0) {
                /* Look backward for 'struct' keyword or _s suffix */
                for (int j = i - 1; j >= 0 && j >= i - 10; j--) {
                    if (children[j]->type != AST_TOKEN) continue;
                    if (children[j]->token.type == TOKEN_WHITESPACE ||
                        children[j]->token.type == TOKEN_COMMENT) continue;
                    
                    const char *prev_text = children[j]->token.text;
                    
                    /* Check for 'struct' keyword */
                    if (children[j]->token.type == TOKEN_KEYWORD &&
                        strcmp(prev_text, "struct") == 0) {
                        return 1;  /* Inside struct definition */
                    }
                    
                    /* Check for identifier ending with _s (our struct naming convention) */
                    size_t len = strlen(prev_text);
                    if (len > 2 && strcmp(prev_text + len - 2, "_s") == 0) {
                        return 1;  /* Inside struct definition */
                    }
                    
                    break;  /* Found something else, not a struct */
                }
                return 0;
            }
        }
    }
    
    return 0;
}

/* Check if this is a variable/parameter declaration context */
static int is_declaration_context(ASTNode **children, size_t count, size_t type_idx) {
    /* Look at what follows the type */
    size_t next_idx = skip_ws(children, count, type_idx + 1);
    if (next_idx >= count || children[next_idx]->type != AST_TOKEN) {
        return 0;
    }
    
    const char *next_text = children[next_idx]->token.text;
    
    /* If immediately followed by semicolon, it's likely a typedef name, not a declaration */
    if (strcmp(next_text, ";") == 0) {
        return 0;
    }
    
    /* Followed by identifier, *, ), or , -> likely a declaration */
    if (children[next_idx]->token.type == TOKEN_IDENTIFIER ||
        strcmp(next_text, "*") == 0 ||
        strcmp(next_text, ")") == 0 ||
        strcmp(next_text, ",") == 0) {
        return 1;
    }
    
    return 0;
}

/* Check if this token is preceded by 'mut' keyword */
static int has_mut_before(ASTNode **children, size_t idx) {
    if (idx == 0) return 0;
    
    /* Skip whitespace/comments backward */
    size_t prev_idx = idx - 1;
    while (prev_idx > 0 && children[prev_idx]->type == AST_TOKEN &&
           (children[prev_idx]->token.type == TOKEN_WHITESPACE ||
            children[prev_idx]->token.type == TOKEN_COMMENT)) {
        if (prev_idx == 0) break;
        prev_idx--;
    }
    
    if (children[prev_idx]->type == AST_TOKEN &&
        children[prev_idx]->token.type == TOKEN_IDENTIFIER &&
        strcmp(children[prev_idx]->token.text, "mut") == 0) {
        return 1;
    }
    
    return 0;
}

/* Check if this is a CZar type that will be transformed later */
static int is_czar_type(const char *text) {
    return (strcmp(text, "u8") == 0 ||
            strcmp(text, "u16") == 0 ||
            strcmp(text, "u32") == 0 ||
            strcmp(text, "u64") == 0 ||
            strcmp(text, "i8") == 0 ||
            strcmp(text, "i16") == 0 ||
            strcmp(text, "i32") == 0 ||
            strcmp(text, "i64") == 0 ||
            strcmp(text, "usize") == 0 ||
            strcmp(text, "isize") == 0 ||
            strcmp(text, "f32") == 0 ||
            strcmp(text, "f64") == 0);
}

/* Check if this looks like a type keyword (only C types, not CZar types) */
static int is_type_keyword(Token *token) {
    const char *text = token->text;
    size_t len = strlen(text);
    
    /* Skip CZar types - they will be transformed later and we can't modify them */
    if (is_czar_type(text)) {
        return 0;
    }
    
    /* C keywords */
    if (token->type == TOKEN_KEYWORD &&
        (strcmp(text, "void") == 0 ||
         strcmp(text, "char") == 0 ||
         strcmp(text, "int") == 0 ||
         strcmp(text, "short") == 0 ||
         strcmp(text, "long") == 0 ||
         strcmp(text, "float") == 0 ||
         strcmp(text, "double") == 0 ||
         strcmp(text, "signed") == 0 ||
         strcmp(text, "unsigned") == 0 ||
         strcmp(text, "bool") == 0)) {
        return 1;
    }
    
    /* Already-transformed C types */
    if (token->type == TOKEN_IDENTIFIER &&
        (strcmp(text, "uint8_t") == 0 ||
         strcmp(text, "uint16_t") == 0 ||
         strcmp(text, "uint32_t") == 0 ||
         strcmp(text, "uint64_t") == 0 ||
         strcmp(text, "int8_t") == 0 ||
         strcmp(text, "int16_t") == 0 ||
         strcmp(text, "int32_t") == 0 ||
         strcmp(text, "int64_t") == 0 ||
         strcmp(text, "size_t") == 0 ||
         strcmp(text, "ptrdiff_t") == 0)) {
        return 1;
    }
    
    /* Custom types (identifiers ending in _t) */
    if (token->type == TOKEN_IDENTIFIER && len > 2 &&
        strcmp(text + len - 2, "_t") == 0) {
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

/* Check if we're in a function parameter list context */
static int is_in_function_params(ASTNode **children, size_t idx) {
    /* Look backward for opening ( and check context */
    int paren_count = 0;
    
    for (int i = (int)idx - 1; i >= 0 && i >= (int)idx - 50; i--) {
        if (children[i]->type == AST_TOKEN) {
            const char *text = children[i]->token.text;
            
            /* Check for statement/block terminators - we're not in function params */
            if (strcmp(text, ";") == 0 || strcmp(text, "{") == 0 || strcmp(text, "}") == 0) {
                return 0;
            }
            
            /* Track parentheses */
            if (strcmp(text, ")") == 0) {
                paren_count++;
            } else if (strcmp(text, "(") == 0) {
                paren_count--;
                if (paren_count < 0) {
                    /* Found opening paren, now check what comes before it */
                    
                    /* First check if there's a for/while/if/switch keyword just before */
                    for (int k = i - 1; k >= 0 && k >= i - 10; k--) {
                        if (children[k]->type == AST_TOKEN) {
                            if (children[k]->token.type == TOKEN_WHITESPACE || 
                                children[k]->token.type == TOKEN_COMMENT) {
                                continue;
                            }
                            /* Check for control flow keywords */
                            if (children[k]->token.type == TOKEN_KEYWORD &&
                                (strcmp(children[k]->token.text, "for") == 0 ||
                                 strcmp(children[k]->token.text, "while") == 0 ||
                                 strcmp(children[k]->token.text, "if") == 0 ||
                                 strcmp(children[k]->token.text, "switch") == 0)) {
                                return 0;  /* This is a control flow statement, not function params */
                            }
                            break;  /* Found something else, stop checking */
                        }
                    }
                    
                    /* Check if it's a function declaration (identifier before paren) */
                    for (int j = i - 1; j >= 0 && j >= i - 10; j--) {
                        if (children[j]->type == AST_TOKEN) {
                            if (children[j]->token.type == TOKEN_WHITESPACE || 
                                children[j]->token.type == TOKEN_COMMENT) {
                                continue;
                            }
                            /* Should be an identifier (function name) */
                            if (children[j]->token.type == TOKEN_IDENTIFIER) {
                                return 1;  /* This is a function parameter */
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

/* Check if we're inside a typedef statement */
static int is_in_typedef(ASTNode **children, size_t count, size_t idx) {
    int found_typedef = 0;
    
    /* Look backward for 'typedef' keyword (before we hit semicolon) */
    for (int i = (int)idx - 1; i >= 0 && i >= (int)idx - 50; i--) {
        if (children[i]->type != AST_TOKEN) continue;
        
        const char *text = children[i]->token.text;
        
        /* If we hit a semicolon, we've gone past a previous statement */
        if (strcmp(text, ";") == 0) {
            break;
        }
        
        /* Check for typedef keyword */
        if (children[i]->token.type == TOKEN_KEYWORD &&
            strcmp(text, "typedef") == 0) {
            found_typedef = 1;
            break;
        }
    }
    
    if (!found_typedef) return 0;
    
    /* Now look forward to see if we're before the closing semicolon */
    for (size_t i = idx + 1; i < count && i < idx + 50; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        
        const char *text = children[i]->token.text;
        
        /* If we find a semicolon ahead, we're still in the typedef */
        if (strcmp(text, ";") == 0) {
            return 1;
        }
    }
    
    return 0;
}

/* Transform mutability keywords */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) return;
    
    /* Pass 1: Add const to non-mut variables by modifying token text directly */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        Token *token = &ast->children[i]->token;
        
        /* Look for type keywords that might need const */
        if (!is_type_keyword(token)) continue;
        
        /* Skip if inside struct definition */
        if (is_inside_struct_definition(ast->children, ast->child_count, i)) {
            continue;
        }
        
        /* Skip if inside typedef */
        if (is_in_typedef(ast->children, ast->child_count, i)) {
            continue;
        }
        
        /* Skip if preceded by 'mut' */
        if (has_mut_before(ast->children, i)) {
            continue;
        }
        
        /* Check if this is in a declaration context */
        if (!is_declaration_context(ast->children, ast->child_count, i)) {
            continue;
        }
        
        /* Add const by modifying the token text */
        char *new_text = malloc(strlen(token->text) + 7);  /* "const " + text + \0 */
        if (new_text) {
            sprintf(new_text, "const %s", token->text);
            free(token->text);
            token->text = new_text;
            token->length = strlen(new_text);
        }
    }
    
    /* Pass 2: Strip mut keyword */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        Token *token = &ast->children[i]->token;
        
        /* Check for 'mut' keyword */
        if (token->type == TOKEN_IDENTIFIER && strcmp(token->text, "mut") == 0) {
            /* Replace mut with empty string */
            free(token->text);
            token->text = strdup("");
            if (!token->text) {
                token->text = malloc(1);
                if (token->text) token->text[0] = '\0';
            }
            token->length = 0;
        }
    }
    
    /* Pass 3: Check for forbidden const keyword */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        Token *token = &ast->children[i]->token;
        
        /* Check for const keyword in source (not the ones we added) */
        /* Since we added const in Pass 1, any remaining standalone const is from source */
        if (token->type == TOKEN_KEYWORD && strcmp(token->text, "const") == 0) {
            /* Check if this const was added by us (it would have a space after it in the token) */
            /* Our added consts are part of "const type" tokens, not standalone */
            /* So standalone const tokens are from source code */
            fprintf(stderr, "[CZAR] Error at line %d: 'const' keyword is not allowed in CZar source code. Omit 'mut' instead.\n", 
                    token->line);
            exit(1);
        }
    }
    
    /* Recursively transform children */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) {
            transpiler_transform_mutability(ast->children[i]);
        }
    }
}

/* Validate mutability rules */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source) {
    /* Validation happens during transformation now */
    (void)ast;
    (void)filename;
    (void)source;
}
