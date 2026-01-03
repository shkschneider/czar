/*
 * CZar - C semantic authority layer
 * Transpiler validation module (transpiler/validation.c)
 *
 * Validates CZar semantic rules and reports errors.
 */

#include "validation.h"
#include "../transpiler.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Maximum lookback distance for finding struct/union/enum keywords before braces */
#define MAX_LOOKBACK_TOKENS 30

/* Global context for error reporting */
static const char *g_filename = NULL;
static const char *g_source = NULL;

/* Check if token text matches */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) {
        return 0;
    }
    return strcmp(token->text, text) == 0;
}

/* Find the current function name by scanning backwards from current position */
static const char *find_current_function(ASTNode **children, size_t count, size_t current) {
    /* Look backwards for a function declaration pattern: type name(...) { */
    int brace_depth = 0;
    const char *function_name = NULL;

    for (size_t i = 0; i < current && i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *tok = &children[i]->token;

        if (tok->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(tok, "{")) {
                brace_depth++;
                /* Check if there's a function name before this brace */
                /* Look for pattern: identifier ( ... ) { */
                for (size_t j = (i > 20 ? i - 20 : 0); j < i; j++) {
                    if (children[j]->type == AST_TOKEN &&
                        children[j]->token.type == TOKEN_IDENTIFIER) {
                        /* Check if followed by ( */
                        size_t k = j + 1;
                        while (k < i && children[k]->type == AST_TOKEN &&
                               children[k]->token.type == TOKEN_WHITESPACE) {
                            k++;
                        }
                        if (k < i && children[k]->type == AST_TOKEN &&
                            children[k]->token.type == TOKEN_PUNCTUATION &&
                            token_text_equals(&children[k]->token, "(")) {
                            function_name = children[j]->token.text;
                        }
                    }
                }
            } else if (token_text_equals(tok, "}")) {
                if (brace_depth > 0) {
                    brace_depth--;
                    if (brace_depth == 0) {
                        function_name = NULL;  /* Exited function */
                    }
                }
            }
        }
    }

    return (brace_depth > 0) ? function_name : NULL;
}

/* Check if a token is a type keyword */
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

/* Check if a token is likely a struct/union/enum keyword */
static int is_aggregate_keyword(const char *text) {
    return strcmp(text, "struct") == 0 ||
           strcmp(text, "union") == 0 ||
           strcmp(text, "enum") == 0;
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

/* Check if we're in a function scope (not in struct/union/enum body) */
static int in_function_scope(ASTNode **children, size_t count, size_t current) {
    int brace_depth = 0;
    size_t last_open_brace_index = 0;
    int found_open_brace = 0;

    /* Scan backwards to find the most recent unclosed { */
    for (size_t i = 0; i < current && i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *tok = &children[i]->token;

        if (tok->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(tok, "{")) {
                brace_depth++;
                last_open_brace_index = i;
                found_open_brace = 1;
            } else if (token_text_equals(tok, "}")) {
                if (brace_depth > 0) {
                    brace_depth--;
                    if (brace_depth == 0) {
                        /* We closed all braces, so there's no unclosed brace anymore */
                        found_open_brace = 0;
                    }
                }
            }
        }
    }

    /* If we're not inside any braces, we're at global scope, not function scope */
    if (!found_open_brace || brace_depth == 0) {
        return 0;
    }

    /* Now check if the last unclosed { is a struct/union/enum definition */
    /* Look backward from last_open_brace_index for struct/union/enum keyword */
    for (size_t j = (last_open_brace_index > MAX_LOOKBACK_TOKENS ? last_open_brace_index - MAX_LOOKBACK_TOKENS : 0);
         j < last_open_brace_index; j++) {
        if (children[j]->type != AST_TOKEN) continue;
        Token *prev = &children[j]->token;

        /* If we find a struct/union/enum keyword */
        if ((prev->type == TOKEN_KEYWORD || prev->type == TOKEN_IDENTIFIER) &&
            is_aggregate_keyword(prev->text)) {
            /* Make sure there's no semicolon between keyword and brace */
            int has_semicolon = 0;
            for (size_t k = j + 1; k < last_open_brace_index; k++) {
                if (children[k]->type == AST_TOKEN &&
                    children[k]->token.type == TOKEN_PUNCTUATION &&
                    token_text_equals(&children[k]->token, ";")) {
                    has_semicolon = 1;
                    break;
                }
            }
            if (!has_semicolon) {
                /* This is a struct definition, so we're NOT in function scope */
                return 0;
            }
        }
    }

    /* We're inside braces and it's not a struct, so we're in function scope */
    return 1;
}

/* Validate variable declarations for zero-initialization */
static void validate_variable_declarations(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Skip if not an identifier that could be a type */
        if (token->type != TOKEN_IDENTIFIER && token->type != TOKEN_KEYWORD) {
            continue;
        }

        /* Check if this looks like a type keyword */
        if (!is_type_keyword(token->text) && !is_aggregate_keyword(token->text)) {
            continue;
        }

        /* Check if we're in a function scope */
        if (!in_function_scope(children, count, i)) {
            continue;
        }

        /* Record if this is an aggregate type */
        int is_aggregate = is_aggregate_keyword(token->text);

        /* Find the variable name after the type */
        size_t j = skip_whitespace(children, count, i + 1);

        /* For struct/union/enum, skip the tag name */
        if (is_aggregate && j < count && children[j]->type == AST_TOKEN &&
            children[j]->token.type == TOKEN_IDENTIFIER) {
            /* This is the tag name (e.g., "Point" in "struct Point p") */
            j = skip_whitespace(children, count, j + 1);
        }

        /* Handle const, volatile, etc. */
        while (j < count && children[j]->type == AST_TOKEN) {
            Token *mod = &children[j]->token;
            if (mod->type == TOKEN_KEYWORD &&
                (strcmp(mod->text, "const") == 0 ||
                 strcmp(mod->text, "volatile") == 0 ||
                 strcmp(mod->text, "static") == 0 ||
                 strcmp(mod->text, "register") == 0 ||
                 strcmp(mod->text, "auto") == 0)) {
                j = skip_whitespace(children, count, j + 1);
            } else {
                break;
            }
        }

        /* Handle pointer types */
        while (j < count && children[j]->type == AST_TOKEN &&
               children[j]->token.type == TOKEN_OPERATOR &&
               token_text_equals(&children[j]->token, "*")) {
            j = skip_whitespace(children, count, j + 1);
        }

        /* Get the variable name */
        if (j >= count || children[j]->type != AST_TOKEN ||
            children[j]->token.type != TOKEN_IDENTIFIER) {
            continue;
        }

        Token *var_name = &children[j]->token;

        /* Check what comes after the variable name */
        j = skip_whitespace(children, count, j + 1);

        if (j >= count || children[j]->type != AST_TOKEN) {
            continue;
        }

        Token *next = &children[j]->token;

        /* Check for array declarations */
        if (next->type == TOKEN_PUNCTUATION && token_text_equals(next, "[")) {
            /* Find the closing bracket */
            int bracket_depth = 1;
            j = skip_whitespace(children, count, j + 1);
            while (j < count && bracket_depth > 0) {
                if (children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_PUNCTUATION) {
                    if (token_text_equals(&children[j]->token, "[")) {
                        bracket_depth++;
                    } else if (token_text_equals(&children[j]->token, "]")) {
                        bracket_depth--;
                    }
                }
                j++;
            }
            j = skip_whitespace(children, count, j);
            if (j < count && children[j]->type == AST_TOKEN) {
                next = &children[j]->token;
            } else {
                continue;
            }
        }

        /* Check if variable is initialized */
        if (next->type == TOKEN_OPERATOR && token_text_equals(next, "=")) {
            /* Variable is initialized - check if it's a struct/union/enum with {0} */
            if (is_aggregate) {
                /* Look for initialization value */
                j = skip_whitespace(children, count, j + 1);
                if (j < count && children[j]->type == AST_TOKEN) {
                    Token *init = &children[j]->token;
                    /* Check if it starts with { */
                    if (init->type == TOKEN_PUNCTUATION && token_text_equals(init, "{")) {
                        /* For structs, we should check if it's {0} or similar */
                        /* This is a simple check - we'll allow any brace initialization */
                        continue;
                    }
                }
            }
            continue; /* Variable is initialized */
        } else if (next->type == TOKEN_PUNCTUATION && token_text_equals(next, ";")) {
            /* Variable is NOT initialized - this is an error in CZar! */
            const char *func_name = find_current_function(children, count, i);
            char error_msg[512];
            if (func_name) {
                snprintf(error_msg, sizeof(error_msg),
                         ERR_VARIABLE_NOT_INITIALIZED_IN_FUNC,
                         func_name, var_name->text, token->text, var_name->text,
                         is_aggregate ? " or = {0};" : "");
            } else {
                snprintf(error_msg, sizeof(error_msg),
                         ERR_VARIABLE_NOT_INITIALIZED,
                         var_name->text, token->text, var_name->text,
                         is_aggregate ? " or = {0};" : "");
            }
            cz_error(g_filename, g_source, var_name->line, error_msg);
        } else if (next->type == TOKEN_PUNCTUATION && token_text_equals(next, ",")) {
            /* Multiple declarations in one statement - check each */
            const char *func_name = find_current_function(children, count, i);
            char error_msg[512];
            if (func_name) {
                snprintf(error_msg, sizeof(error_msg),
                         ERR_VARIABLE_NOT_INITIALIZED_MULTI_IN_FUNC,
                         func_name, var_name->text);
            } else {
                snprintf(error_msg, sizeof(error_msg),
                         ERR_VARIABLE_NOT_INITIALIZED_MULTI,
                         var_name->text);
            }
            cz_error(g_filename, g_source, var_name->line, error_msg);
        }
    }
}

/* Validate AST for CZar semantic rules */
void transpiler_validate(ASTNode *ast, const char *filename, const char *source) {
    if (!ast) {
        return;
    }

    /* Set global context for error reporting */
    g_filename = filename;
    g_source = source;

    /* Validate variable declarations */
    validate_variable_declarations(ast);
}
