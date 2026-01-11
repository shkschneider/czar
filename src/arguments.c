/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles named arguments (labels only) transformation.
 */

#include "cz.h"
#include "arguments.h"
#include "errors.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Maximum function declarations we can track */
#define MAX_FUNCTIONS 256
#define MAX_PARAMS 32

/* Function parameter info */
typedef struct {
    char *name;
    char *type;  /* Parameter type for ambiguity checking */
} ParamInfo;

/* Function declaration info */
typedef struct {
    char *name;
    ParamInfo params[MAX_PARAMS];
    int param_count;
} FunctionInfo;

/* Global tracking */
static FunctionInfo g_functions[MAX_FUNCTIONS];
static int g_function_count = 0;

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

/* Register a function declaration with its parameters */
static void register_function(const char *func_name, ParamInfo *params, int param_count) {
    if (g_function_count >= MAX_FUNCTIONS) {
        return;
    }

    /* Check if already registered */
    for (int i = 0; i < g_function_count; i++) {
        if (g_functions[i].name && strcmp(g_functions[i].name, func_name) == 0) {
            return; /* Already registered */
        }
    }

    FunctionInfo *func = &g_functions[g_function_count];
    func->name = strdup(func_name);
    func->param_count = param_count;

    for (int i = 0; i < param_count && i < MAX_PARAMS; i++) {
        func->params[i].name = params[i].name ? strdup(params[i].name) : NULL;
        func->params[i].type = params[i].type ? strdup(params[i].type) : NULL;
    }

    g_function_count++;
}

/* Find a registered function by name */
static FunctionInfo *find_function(const char *func_name) {
    for (int i = 0; i < g_function_count; i++) {
        if (g_functions[i].name && strcmp(g_functions[i].name, func_name) == 0) {
            return &g_functions[i];
        }
    }
    return NULL;
}

/* Check if a token is a type keyword or identifier */
static int is_type_token(Token *token) {
    if (!token || !token->text) return 0;

    if (token->type == TOKEN_KEYWORD) return 1;
    if (token->type != TOKEN_IDENTIFIER) return 0;

    /* Check common type names */
    const char *text = token->text;
    return (strcmp(text, "void") == 0 || strcmp(text, "int") == 0 ||
            strcmp(text, "char") == 0 || strcmp(text, "short") == 0 ||
            strcmp(text, "long") == 0 || strcmp(text, "float") == 0 ||
            strcmp(text, "double") == 0 || strcmp(text, "unsigned") == 0 ||
            strcmp(text, "signed") == 0 || strcmp(text, "u8") == 0 ||
            strcmp(text, "u16") == 0 || strcmp(text, "u32") == 0 ||
            strcmp(text, "u64") == 0 || strcmp(text, "i8") == 0 ||
            strcmp(text, "i16") == 0 || strcmp(text, "i32") == 0 ||
            strcmp(text, "i64") == 0 || strcmp(text, "size_t") == 0 ||
            strcmp(text, "bool") == 0 || strcmp(text, "const") == 0 ||
            strcmp(text, "static") == 0 || strcmp(text, "struct") == 0 ||
            strcmp(text, "enum") == 0 || strcmp(text, "union") == 0);
}

/* Scan for function declarations and register parameter names */
static void scan_function_declarations(ASTNode **children, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (children[i]->token.type != TOKEN_IDENTIFIER) continue;

        Token *tok = &children[i]->token;

        /* Look for function name followed by ( */
        size_t j = skip_whitespace(children, count, i + 1);
        if (j >= count) continue;
        if (children[j]->type != AST_TOKEN) continue;
        if (!token_text_equals(&children[j]->token, "(")) continue;

        /* Check if this is a function declaration by looking backward for return type */
        int is_function_decl = 0;
        for (int k = (int)i - 1; k >= 0 && k >= (int)i - 10; k--) {
            if (children[k]->type != AST_TOKEN) continue;
            if (children[k]->token.type == TOKEN_WHITESPACE ||
                children[k]->token.type == TOKEN_COMMENT) continue;

            if (is_type_token(&children[k]->token)) {
                is_function_decl = 1;
                break;
            }
            break;
        }

        if (!is_function_decl) continue;

        /* Parse parameter list */
        const char *func_name = tok->text;
        ParamInfo params[MAX_PARAMS];
        int param_count = 0;

        int paren_depth = 1;
        j++;

        while (j < count && paren_depth > 0 && param_count < MAX_PARAMS) {
            if (children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_PUNCTUATION) {
                if (token_text_equals(&children[j]->token, "(")) {
                    paren_depth++;
                } else if (token_text_equals(&children[j]->token, ")")) {
                    paren_depth--;
                }
            }

            /* Look for parameter name (identifier after type) */
            if (paren_depth == 1 && children[j]->type == AST_TOKEN) {
                Token *t = &children[j]->token;

                /* If we see a type, look ahead for the parameter name */
                if (is_type_token(t)) {
                    const char *param_type = t->text;
                    size_t k = skip_whitespace(children, count, j + 1);

                    /* Skip pointer markers */
                    while (k < count && children[k]->type == AST_TOKEN &&
                           children[k]->token.type == TOKEN_OPERATOR &&
                           token_text_equals(&children[k]->token, "*")) {
                        k = skip_whitespace(children, count, k + 1);
                    }

                    /* Get parameter name */
                    if (k < count && children[k]->type == AST_TOKEN &&
                        children[k]->token.type == TOKEN_IDENTIFIER) {
                        params[param_count].name = children[k]->token.text;
                        params[param_count].type = strdup(param_type);
                        if (!params[param_count].type) {
                            /* Memory allocation failed, skip this parameter */
                            continue;
                        }
                        param_count++;
                    }
                }
            }

            j++;
        }

        /* Register the function */
        if (param_count > 0) {
            register_function(func_name, params, param_count);
        }
    }
}

/* Transform named arguments in a function call */
static void transform_function_call(ASTNode **children, size_t count, size_t call_pos) {
    /* call_pos points to the function name */
    if (call_pos >= count) return;
    if (children[call_pos]->type != AST_TOKEN) return;

    const char *func_name = children[call_pos]->token.text;
    FunctionInfo *func_info = find_function(func_name);

    /* Find opening paren */
    size_t j = skip_whitespace(children, count, call_pos + 1);
    if (j >= count || children[j]->type != AST_TOKEN) return;
    if (!token_text_equals(&children[j]->token, "(")) return;

    j++;

    /* First pass: collect info about arguments */
    int arg_labeled[MAX_PARAMS] = {0};  /* Track which args have labels */
    int arg_count = 0;
    int paren_depth = 1;
    int arg_index = 0;
    size_t scan_j = j;

    while (scan_j < count && paren_depth > 0 && arg_index < MAX_PARAMS) {
        if (children[scan_j]->type != AST_TOKEN) {
            scan_j++;
            continue;
        }

        Token *t = &children[scan_j]->token;

        /* Track parentheses */
        if (t->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(t, "(")) {
                paren_depth++;
            } else if (token_text_equals(t, ")")) {
                paren_depth--;
                if (paren_depth == 0) {
                    arg_count = arg_index + 1;
                    break;
                }
            } else if (token_text_equals(t, ",") && paren_depth == 1) {
                arg_index++;
            }
        }

        /* Check if this argument has a label */
        if (paren_depth == 1 && t->type == TOKEN_IDENTIFIER) {
            size_t k = skip_whitespace(children, count, scan_j + 1);
            if (k < count && children[k]->type == AST_TOKEN &&
                children[k]->token.type == TOKEN_OPERATOR &&
                token_text_equals(&children[k]->token, "=")) {
                arg_labeled[arg_index] = 1;
            }
        }

        scan_j++;
    }

    /* Check for ambiguous consecutive same-type parameters */
    if (func_info && arg_count >= 2) {
        for (int i = 0; i < func_info->param_count - 1 && i < arg_count - 1; i++) {
            /* Check if consecutive parameters have the same type */
            if (func_info->params[i].type && func_info->params[i + 1].type &&
                strcmp(func_info->params[i].type, func_info->params[i + 1].type) == 0) {

                /* Check if both arguments are unlabeled */
                if (!arg_labeled[i] && !arg_labeled[i + 1]) {
                    /* Found ambiguous parameters - issue error */
                    /* Only error if parameter names are available */
                    if (func_info->params[i].name && func_info->params[i + 1].name) {
                        char error_msg[256];
                        char suggestion[128];
                        snprintf(suggestion, sizeof(suggestion),
                                "%s(%s = ..., %s = ...)",
                                func_name,
                                func_info->params[i].name,
                                func_info->params[i + 1].name);
                        snprintf(error_msg, sizeof(error_msg),
                                ERR_AMBIGUOUS_ARGUMENTS, suggestion);
                        cz_error(g_filename, g_source, children[call_pos]->token.line, error_msg);
                    }
                    break;  /* Only error once per function call */
                }
            }
        }
    }

    /* Second pass: transform named arguments */
    paren_depth = 1;
    arg_index = 0;

    while (j < count && paren_depth > 0) {
        if (children[j]->type != AST_TOKEN) {
            j++;
            continue;
        }

        Token *t = &children[j]->token;

        /* Track parentheses */
        if (t->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(t, "(")) {
                paren_depth++;
            } else if (token_text_equals(t, ")")) {
                paren_depth--;
                if (paren_depth == 0) break;
            } else if (token_text_equals(t, ",") && paren_depth == 1) {
                arg_index++;
            }
        }

        /* Look for pattern: identifier = value */
        if (paren_depth == 1 && t->type == TOKEN_IDENTIFIER) {
            size_t k = skip_whitespace(children, count, j + 1);
            if (k < count && children[k]->type == AST_TOKEN &&
                children[k]->token.type == TOKEN_OPERATOR &&
                token_text_equals(&children[k]->token, "=")) {

                /* This is a named argument! */
                const char *label = t->text;

                /* Validate the label matches the expected parameter name */
                if (func_info) {
                    if (arg_index < func_info->param_count) {
                        const char *expected_param = func_info->params[arg_index].name;
                        if (expected_param && strcmp(label, expected_param) != 0) {
                            /* Error: label doesn't match parameter name or order */
                            char error_msg[512];
                            snprintf(error_msg, sizeof(error_msg),
                                    "Named argument '%s' at position %d does not match expected parameter '%s'. "
                                    "Named arguments must preserve parameter order.",
                                    label, arg_index + 1, expected_param);
                            cz_error(g_filename, g_source, t->line, error_msg);
                        }
                    }
                } else {
                    /* Function not found - might be external or defined later */
                    /* We'll allow it but can't validate */
                }

                /* Strip the label, =, and any whitespace after = */
                /* Strip the label */
                free(t->text);
                t->text = strdup("");
                t->length = 0;

                /* Strip whitespace between label and = */
                for (size_t m = j + 1; m < k; m++) {
                    if (children[m]->type == AST_TOKEN &&
                        children[m]->token.type == TOKEN_WHITESPACE) {
                        free(children[m]->token.text);
                        children[m]->token.text = strdup("");
                        children[m]->token.length = 0;
                    }
                }

                /* Strip the = operator */
                free(children[k]->token.text);
                children[k]->token.text = strdup("");
                children[k]->token.length = 0;

                /* Strip whitespace after = */
                size_t m = k + 1;
                while (m < count && children[m]->type == AST_TOKEN &&
                       children[m]->token.type == TOKEN_WHITESPACE) {
                    free(children[m]->token.text);
                    children[m]->token.text = strdup("");
                    children[m]->token.length = 0;
                    m++;
                }
            }
        }

        j++;
    }
}

/* Transform named arguments by stripping labels */
void transpiler_transform_named_arguments(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    g_filename = filename;
    g_source = source;
    g_function_count = 0;

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    /* First pass: scan for function declarations */
    scan_function_declarations(children, count);

    /* Second pass: transform function calls with named arguments */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (children[i]->token.type != TOKEN_IDENTIFIER) continue;

        const char *identifier = children[i]->token.text;

        /* Skip control flow keywords that use parentheses but are not function calls */
        if (identifier && (strcmp(identifier, "for") == 0 ||
                          strcmp(identifier, "while") == 0 ||
                          strcmp(identifier, "if") == 0 ||
                          strcmp(identifier, "switch") == 0 ||
                          strcmp(identifier, "sizeof") == 0)) {
            continue;
        }

        /* Look for function call pattern: identifier ( */
        size_t j = skip_whitespace(children, count, i + 1);
        if (j >= count) continue;
        if (children[j]->type != AST_TOKEN) continue;
        if (!token_text_equals(&children[j]->token, "(")) continue;

        /* Check if this is NOT a function declaration */
        int is_declaration = 0;
        for (int k = (int)i - 1; k >= 0 && k >= (int)i - 10; k--) {
            if (children[k]->type != AST_TOKEN) continue;
            if (children[k]->token.type == TOKEN_WHITESPACE ||
                children[k]->token.type == TOKEN_COMMENT) continue;

            if (is_type_token(&children[k]->token)) {
                is_declaration = 1;
                break;
            }
            break;
        }

        if (!is_declaration) {
            /* This is a function call */
            transform_function_call(children, count, i);
        }
    }

    /* Cleanup */
    for (int i = 0; i < g_function_count; i++) {
        free(g_functions[i].name);
        for (int j = 0; j < g_functions[i].param_count; j++) {
            free(g_functions[i].params[j].name);
            free(g_functions[i].params[j].type);
        }
    }
    g_function_count = 0;
}
