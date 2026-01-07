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
static int is_inside_struct_definition(ASTNode **children, size_t idx) {
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

/* Check if this type is a function return type */
static int is_function_return_type(ASTNode **children, size_t count, size_t type_idx) {
    /* Strategy: Look forward to see if we have: Type identifier ( (no * between type and identifier) */
    size_t idx = type_idx + 1;
    int saw_pointer = 0;
    
    /* Skip whitespace and track pointer markers */
    while (idx < count && children[idx]->type == AST_TOKEN) {
        const char *text = children[idx]->token.text;
        TokenType type = children[idx]->token.type;
        
        if (type == TOKEN_WHITESPACE || type == TOKEN_COMMENT) {
            idx++;
            continue;
        }
        
        if (strcmp(text, "*") == 0) {
            saw_pointer = 1;
            idx++;
            continue;
        }
        
        /* If we hit an identifier */
        if (type == TOKEN_IDENTIFIER) {
            /* If we saw a pointer marker, this is likely a pointer variable, not a function */
            if (saw_pointer) {
                return 0;
            }
            
            /* Check if identifier is followed by '(' */
            size_t next_idx = idx + 1;
            while (next_idx < count && children[next_idx]->type == AST_TOKEN &&
                   (children[next_idx]->token.type == TOKEN_WHITESPACE ||
                    children[next_idx]->token.type == TOKEN_COMMENT)) {
                next_idx++;
            }
            
            if (next_idx < count && children[next_idx]->type == AST_TOKEN) {
                const char *next_text = children[next_idx]->token.text;
                if (next_text && strcmp(next_text, "(") == 0) {
                    return 1;  /* Type identifier( pattern - function return type */
                }
            }
            
            /* Identifier not followed by '(' - it's a variable, not a function */
            return 0;
        }
        
        /* Hit something else, not a function return type */
        break;
    }
    
    return 0;
}

/* Check if this is a variable/parameter declaration context */
static int is_declaration_context(ASTNode **children, size_t count, size_t type_idx) {
    /* Skip function return types */
    if (is_function_return_type(children, count, type_idx)) {
        return 0;
    }
    
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

/* Check if this type declaration is for a 'self' parameter */
static int is_self_parameter(ASTNode **children, size_t count, size_t type_idx) {
    /* Look forward for 'self' identifier after the type */
    size_t idx = skip_ws(children, count, type_idx + 1);
    
    /* Skip pointer markers */
    while (idx < count && children[idx]->type == AST_TOKEN) {
        if (strcmp(children[idx]->token.text, "*") == 0) {
            idx = skip_ws(children, count, idx + 1);
        } else {
            break;
        }
    }
    
    /* Check if the next identifier is 'self' */
    if (idx < count && children[idx]->type == AST_TOKEN &&
        children[idx]->token.type == TOKEN_IDENTIFIER &&
        strcmp(children[idx]->token.text, "self") == 0) {
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

    /* Strip "const " prefix if present */
    if (strncmp(text, "const ", 6) == 0) {
        text += 6;
        len -= 6;
    }

    /* Skip CZar types - they will be transformed later and we can't modify them */
    if (is_czar_type(text)) {
        return 0;
    }

    /* C keywords */
    if ((token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER) &&
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
        if (is_inside_struct_definition(ast->children, i)) {
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

        /* Skip if preceded by another type keyword (multi-word types like unsigned long) */
        size_t prev_idx = i;
        while (prev_idx > 0) {
            prev_idx--;
            if (ast->children[prev_idx]->type != AST_TOKEN) break;
            Token *prev_token = &ast->children[prev_idx]->token;
            
            if (prev_token->type == TOKEN_WHITESPACE || prev_token->type == TOKEN_COMMENT) {
                continue;
            }
            
            /* If previous non-whitespace token is a type keyword, skip adding const */
            if (is_type_keyword(prev_token)) {
                goto skip_multi_word_type;
            }
            
            break;
        }

        /* Skip if this is a 'self' parameter (methods need mutable self) */
        if (is_self_parameter(ast->children, ast->child_count, i)) {
            continue;
        }

        /* Check if this is in a declaration context */
        if (!is_declaration_context(ast->children, ast->child_count, i)) {
            continue;
        }

        /* Skip if this is part of a cast expression: (Type) or (Type1 Type2) */
        /* Look backward to find if we're inside parentheses */
        int in_parens = 0;
        for (size_t j = i; j > 0 && j > (i > 30 ? i - 30 : 0); j--) {
            if (ast->children[j-1]->type != AST_TOKEN) continue;
            const char *prev_text = ast->children[j-1]->token.text;
            
            if (strcmp(prev_text, ")") == 0) {
                break;  /* Hit a closing paren before finding opening */
            }
            if (strcmp(prev_text, "(") == 0) {
                in_parens = 1;
                break;
            }
        }
        
        if (in_parens) {
            /* Check if everything between ( and next ) is types/keywords */
            /* This indicates a cast expression */
            size_t forward_idx = i + 1;
            int found_close_paren = 0;
            int only_types = 1;
            
            while (forward_idx < ast->child_count && forward_idx < i + 20) {
                if (ast->children[forward_idx]->type != AST_TOKEN) break;
                Token *fwd_token = &ast->children[forward_idx]->token;
                const char *fwd_text = fwd_token->text;
                
                if (strcmp(fwd_text, ")") == 0) {
                    found_close_paren = 1;
                    break;
                }
                
                /* Allow type keywords, *, and whitespace */
                if (fwd_token->type != TOKEN_WHITESPACE &&
                    fwd_token->type != TOKEN_COMMENT &&
                    strcmp(fwd_text, "*") != 0 &&
                    !is_type_keyword(fwd_token)) {
                    only_types = 0;
                    break;
                }
                
                forward_idx++;
            }
            
            if (found_close_paren && only_types) {
                continue;  /* Skip const for cast expressions */
            }
        }

        /* Don't add const to 'void' in function parameters like func(void) or main(void) */
        if (strcmp(token->text, "void") == 0) {
            /* Check if this void is a sole parameter (void) or main(void) pattern */
            /* Look backward for ( - only check recent tokens */
            int found_open_paren = 0;
            size_t start_j = (i > 10) ? (i - 10) : 0;
            for (size_t j = i; j > start_j; j--) {
                if (ast->children[j-1]->type != AST_TOKEN) continue;
                const char *prev_text = ast->children[j-1]->token.text;
                TokenType prev_type = ast->children[j-1]->token.type;
                
                if (strcmp(prev_text, "(") == 0) {
                    found_open_paren = 1;
                    break;
                }
                /* If we hit something that's not whitespace/comment, stop */
                if (prev_type != TOKEN_WHITESPACE && prev_type != TOKEN_COMMENT) {
                    break;
                }
            }
            
            if (found_open_paren) {
                /* Look forward for ) */
                size_t next_idx = skip_ws(ast->children, ast->child_count, i + 1);
                if (next_idx < ast->child_count && ast->children[next_idx]->type == AST_TOKEN &&
                    strcmp(ast->children[next_idx]->token.text, ")") == 0) {
                    continue;  /* Skip const for func(void) */
                }
            }
        }

        /* Add const by modifying the token text */
        char *new_text = malloc(strlen(token->text) + 7);  /* "const " + text + \0 */
        if (new_text) {
            sprintf(new_text, "const %s", token->text);
            free(token->text);
            token->text = new_text;
            token->length = strlen(new_text);
        }

skip_multi_word_type:
        continue;
    }

    /* Pass 1.5: Add const after * for non-mut pointer variables/parameters */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        Token *token = &ast->children[i]->token;

        /* Look for * that might need const after it */
        if (strcmp(token->text, "*") != 0) continue;

        /* Skip if preceded by 'mut' (need to check before the type) */
        /* Look back to find the type token */
        size_t type_idx = i;
        while (type_idx > 0) {
            type_idx--;
            if (ast->children[type_idx]->type != AST_TOKEN) continue;
            Token *prev_token = &ast->children[type_idx]->token;
            
            /* Skip whitespace */
            if (prev_token->type == TOKEN_WHITESPACE || prev_token->type == TOKEN_COMMENT) {
                continue;
            }
            
            /* Found the type */
            if (is_type_keyword(prev_token) || 
                (prev_token->type == TOKEN_IDENTIFIER && strstr(prev_token->text, "const ") == prev_token->text)) {
                /* Check if this type has mut before it */
                if (has_mut_before(ast->children, type_idx)) {
                    goto skip_pointer_const;
                }
                break;
            }
            
            /* Hit something else */
            break;
        }

        /* Skip if this is a function return type pointer */
        /* Walk back to find the start of this declaration */
        int paren_depth = 0;
        for (int j = (int)i - 1; j >= 0 && j >= (int)i - 20; j--) {
            if (ast->children[j]->type != AST_TOKEN) continue;
            const char *text = ast->children[j]->token.text;
            
            if (strcmp(text, ")") == 0) paren_depth++;
            else if (strcmp(text, "(") == 0) paren_depth--;
            
            /* If we hit a type and are not inside parens */
            if (paren_depth == 0 && is_type_keyword(&ast->children[j]->token)) {
                /* Check if this type is a function return type */
                if (is_function_return_type(ast->children, ast->child_count, j)) {
                    goto skip_pointer_const;
                }
                break;
            }
        }

        /* Skip if inside struct definition */
        if (is_inside_struct_definition(ast->children, i)) {
            goto skip_pointer_const;
        }

        /* Skip if this is a cast expression: (Type*) */
        /* Check if preceded by '(' */
        size_t check_idx = i;
        int found_open_paren = 0;
        while (check_idx > 0) {
            check_idx--;
            if (ast->children[check_idx]->type != AST_TOKEN) continue;
            Token *check_token = &ast->children[check_idx]->token;
            
            if (check_token->type == TOKEN_WHITESPACE || check_token->type == TOKEN_COMMENT) {
                continue;
            }
            
            if (strcmp(check_token->text, "(") == 0) {
                found_open_paren = 1;
            }
            break;
        }
        
        if (found_open_paren) {
            /* Check if followed by ')' after optional whitespace */
            size_t close_idx = skip_ws(ast->children, ast->child_count, i + 1);
            if (close_idx < ast->child_count && ast->children[close_idx]->type == AST_TOKEN &&
                strcmp(ast->children[close_idx]->token.text, ")") == 0) {
                goto skip_pointer_const;  /* It's a cast: (Type*) */
            }
        }

        /* Check if followed by identifier (variable/parameter name) */
        size_t next_idx = skip_ws(ast->children, ast->child_count, i + 1);
        if (next_idx >= ast->child_count || ast->children[next_idx]->type != AST_TOKEN) {
            goto skip_pointer_const;
        }
        
        Token *next_token = &ast->children[next_idx]->token;
        
        /* Must be followed by identifier or another * */
        if (next_token->type != TOKEN_IDENTIFIER && strcmp(next_token->text, "*") != 0) {
            goto skip_pointer_const;
        }

        /* Add " const" after the * by modifying token text */
        char *new_text = malloc(strlen(token->text) + 7);  /* "* const" */
        if (new_text) {
            sprintf(new_text, "* const");
            free(token->text);
            token->text = new_text;
            token->length = strlen(new_text);
        }

skip_pointer_const:
        continue;
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
