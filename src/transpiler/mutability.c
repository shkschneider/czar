/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Transforms mutability keywords for C compilation.
 * Strategy: Strip 'mut' and add 'const' for immutable variables.
 * Let the C compiler handle all validation.
 */

#define _POSIX_C_SOURCE 200809L

#include "mutability.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Helper: Compare token text */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) {
        return 0;
    }
    return strcmp(token->text, text) == 0;
}

/* Helper: Check if token is a type keyword */
static int is_type_keyword(const char *text) {
    /* C standard types */
    if (strcmp(text, "int") == 0 || strcmp(text, "char") == 0 ||
        strcmp(text, "short") == 0 || strcmp(text, "long") == 0 ||
        strcmp(text, "float") == 0 || strcmp(text, "double") == 0 ||
        strcmp(text, "void") == 0 || strcmp(text, "signed") == 0 ||
        strcmp(text, "unsigned") == 0) {
        return 1;
    }

    /* CZar types (before transformation) */
    if (strcmp(text, "u8") == 0 || strcmp(text, "u16") == 0 ||
        strcmp(text, "u32") == 0 || strcmp(text, "u64") == 0 ||
        strcmp(text, "i8") == 0 || strcmp(text, "i16") == 0 ||
        strcmp(text, "i32") == 0 || strcmp(text, "i64") == 0 ||
        strcmp(text, "f32") == 0 || strcmp(text, "f64") == 0 ||
        strcmp(text, "usize") == 0 || strcmp(text, "isize") == 0) {
        return 1;
    }

    /* CZar types (after transformation to C types) */
    if (strcmp(text, "uint8_t") == 0 || strcmp(text, "uint16_t") == 0 ||
        strcmp(text, "uint32_t") == 0 || strcmp(text, "uint64_t") == 0 ||
        strcmp(text, "int8_t") == 0 || strcmp(text, "int16_t") == 0 ||
        strcmp(text, "int32_t") == 0 || strcmp(text, "int64_t") == 0 ||
        strcmp(text, "size_t") == 0 || strcmp(text, "ptrdiff_t") == 0) {
        return 1;
    }

    return 0;
}

/* Helper: Check if token is an aggregate keyword */
static int is_aggregate_keyword(const char *text) {
    return strcmp(text, "struct") == 0 ||
           strcmp(text, "union") == 0 ||
           strcmp(text, "enum") == 0;
}

/* Helper: Skip whitespace and comment tokens */
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

/* Validate mutability rules - now minimal, just check for 'mut' on struct fields */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    int in_struct_def = 0;

    /* Only validation: ensure struct fields don't have 'mut' */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Track when we enter a struct/union definition */
        if (token->type == TOKEN_IDENTIFIER && 
            (strcmp(token->text, "struct") == 0 || strcmp(token->text, "union") == 0)) {
            size_t j = skip_whitespace(children, count, i + 1);
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_IDENTIFIER) {
                j = skip_whitespace(children, count, j + 1);
            }
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_PUNCTUATION &&
                token_text_equals(&children[j]->token, "{")) {
                in_struct_def = 1;
            }
        }

        /* Track when we exit a struct definition */
        if (in_struct_def && token->type == TOKEN_PUNCTUATION &&
            token_text_equals(token, "}")) {
            size_t j = skip_whitespace(children, count, i + 1);
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_PUNCTUATION &&
                token_text_equals(&children[j]->token, ";")) {
                in_struct_def = 0;
            }
        }

        /* Error if 'mut' is used in struct field definition */
        if (in_struct_def && token->type == TOKEN_IDENTIFIER &&
            token_text_equals(token, "mut")) {
            size_t j = skip_whitespace(children, count, i + 1);
            if (j < count && children[j]->type == AST_TOKEN &&
                (is_type_keyword(children[j]->token.text) || 
                 is_aggregate_keyword(children[j]->token.text))) {
                char error_msg[512];
                snprintf(error_msg, sizeof(error_msg),
                        "Struct fields cannot have 'mut' qualifier. Mutability is determined by the struct instance, not individual fields.");
                cz_error(filename, source, token->line, error_msg);
            }
        }
    }
}

/* Transform mutability keywords:
 * - Strip 'mut' keyword
 * - Add 'const' before types that don't have 'mut'
 */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) {
        return;
    }

    if (ast->type == AST_TRANSLATION_UNIT) {
        ASTNode **children = ast->children;
        size_t count = ast->child_count;

        /* First pass: Mark positions that have 'mut' */
        int *has_mut_marker = calloc(count, sizeof(int));
        if (!has_mut_marker) return;

        for (size_t i = 0; i < count; i++) {
            if (children[i]->type != AST_TOKEN) continue;
            Token *token = &children[i]->token;

            if (token->type == TOKEN_IDENTIFIER && strcmp(token->text, "mut") == 0) {
                /* Check if this is followed by a type */
                size_t j = skip_whitespace(children, count, i + 1);
                if (j < count && children[j]->type == AST_TOKEN &&
                    (is_type_keyword(children[j]->token.text) || 
                     is_aggregate_keyword(children[j]->token.text))) {
                    has_mut_marker[j] = 1;  /* Mark this type position as having mut */
                }
            }
        }

        /* Second pass: Strip 'mut' and add 'const' where appropriate */
        for (size_t i = 0; i < count; i++) {
            if (children[i]->type != AST_TOKEN) {
                transpiler_transform_mutability(children[i]);
                continue;
            }

            Token *token = &children[i]->token;

            /* Strip 'mut' keyword */
            if (token->type == TOKEN_IDENTIFIER && strcmp(token->text, "mut") == 0) {
                size_t j = skip_whitespace(children, count, i + 1);
                if (j < count && children[j]->type == AST_TOKEN &&
                    (is_type_keyword(children[j]->token.text) || 
                     is_aggregate_keyword(children[j]->token.text))) {
                    free(token->text);
                    token->text = strdup("");
                    token->length = 0;
                }
            }
            /* Add 'const' for immutable types (those without 'mut') */
            else if ((token->type == TOKEN_IDENTIFIER || token->type == TOKEN_KEYWORD) &&
                     (is_type_keyword(token->text) || is_aggregate_keyword(token->text))) {
                /* Skip if this type had 'mut' */
                if (has_mut_marker[i]) {
                    continue;
                }
                
                /* Skip if already has 'const' */
                int has_const = 0;
                if (i > 0) {
                    size_t check_idx = i - 1;
                    while (check_idx > 0 && children[check_idx]->type == AST_TOKEN &&
                           (children[check_idx]->token.type == TOKEN_WHITESPACE ||
                            children[check_idx]->token.type == TOKEN_COMMENT)) {
                        check_idx--;
                    }
                    if (children[check_idx]->type == AST_TOKEN &&
                        children[check_idx]->token.type == TOKEN_IDENTIFIER &&
                        strcmp(children[check_idx]->token.text, "const") == 0) {
                        has_const = 1;
                    }
                }
                
                if (!has_const) {
                    /* Skip void type in function parameters */
                    if (strcmp(token->text, "void") == 0) {
                        /* Check if this is in a function parameter list */
                        /* Look for ( before and ) after */
                        int in_params = 0;
                        for (size_t k = (i > 5 ? i - 5 : 0); k < i; k++) {
                            if (children[k]->type == AST_TOKEN &&
                                children[k]->token.type == TOKEN_PUNCTUATION &&
                                token_text_equals(&children[k]->token, "(")) {
                                in_params = 1;
                                break;
                            }
                        }
                        if (in_params) continue;
                    }
                    
                    /* Skip function return types - check if type is followed by identifier then ( */
                    int is_function_return = 0;
                    size_t next_idx = skip_whitespace(children, count, i + 1);
                    if (next_idx < count && children[next_idx]->type == AST_TOKEN &&
                        children[next_idx]->token.type == TOKEN_IDENTIFIER) {
                        /* Found identifier after type, check if it's followed by ( */
                        size_t after_id = skip_whitespace(children, count, next_idx + 1);
                        if (after_id < count && children[after_id]->type == AST_TOKEN &&
                            children[after_id]->token.type == TOKEN_PUNCTUATION &&
                            token_text_equals(&children[after_id]->token, "(")) {
                            is_function_return = 1;
                        }
                    }
                    if (is_function_return) continue;
                    
                    /* Replace the type with "const <type>" */
                    size_t old_len = strlen(token->text);
                    size_t new_len = 6 + old_len; /* "const " + type */
                    char *new_text = malloc(new_len + 1);
                    if (new_text) {
                        snprintf(new_text, new_len + 1, "const %s", token->text);
                        free(token->text);
                        token->text = new_text;
                        token->length = new_len;
                    }
                }
            }
        }

        free(has_mut_marker);
    } else {
        /* Recursively transform children */
        for (size_t i = 0; i < ast->child_count; i++) {
            transpiler_transform_mutability(ast->children[i]);
        }
    }
}
