/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles #defer keyword for scope-exit cleanup using cleanup attribute.
 * Transforms: type var = init() #defer { code };
 * Into: Generated cleanup function + __attribute__((cleanup(...))) type var = init();
 */

#include "cz.h"
#include "defer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Counter for generating unique cleanup function names */
static int defer_counter = 0;

/* Buffer to store generated cleanup functions */
static char *generated_defer_functions = NULL;
static size_t generated_defer_functions_size = 0;

/* Helper to check if token text matches a string */
static int token_matches(Token *tok, const char *str) {
    if (!tok || !tok->text || !str) return 0;
    size_t len = strlen(str);
    return tok->length == len && strncmp(tok->text, str, len) == 0;
}

/* Helper to skip whitespace and comments */
static size_t skip_whitespace(ASTNode_t **children, size_t count, size_t start) {
    if (!children) return count;
    for (size_t i = start; i < count; i++) {
        if (!children[i] || children[i]->type != AST_TOKEN) continue;
        TokenType type = children[i]->token.type;
        if (type != TOKEN_WHITESPACE && type != TOKEN_COMMENT) {
            return i;
        }
    }
    return count;
}

/* Extract variable name from declaration by scanning backwards */
static char* extract_variable_name(ASTNode_t **children, size_t count __attribute__((unused)), size_t defer_pos) {

    /* Scan backwards to find the variable identifier */
    for (size_t j = defer_pos; j > 0; j--) {
        size_t idx = j - 1;
        if (!children[idx] || children[idx]->type != AST_TOKEN) continue;

        Token *t = &children[idx]->token;

        /* Skip whitespace */
        if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) continue;

        /* If we hit a statement boundary (;, {, }) before finding =, it's standalone */
        if (t->type == TOKEN_PUNCTUATION) {
            if (token_matches(t, ";") || token_matches(t, "{") || token_matches(t, "}")) {
                /* No assignment on this statement, it's standalone defer */
                return NULL;
            }
        }

        /* If we hit an equals sign, the identifier should be before it */
        if (t->type == TOKEN_OPERATOR || t->type == TOKEN_PUNCTUATION) {
            if (token_matches(t, "=")) {
                /* Go back to find the identifier */
                for (size_t k = idx; k > 0; k--) {
                    size_t id_idx = k - 1;
                    if (!children[id_idx] || children[id_idx]->type != AST_TOKEN) continue;

                    Token *id_tok = &children[id_idx]->token;
                    if (id_tok->type == TOKEN_WHITESPACE || id_tok->type == TOKEN_COMMENT) continue;


                    if (id_tok->type == TOKEN_IDENTIFIER) {
                        char *name = malloc(id_tok->length + 1);
                        if (name) {
                            memcpy(name, id_tok->text, id_tok->length);
                            name[id_tok->length] = '\0';
                        }
                        return name;
                    }

                    /* Skip over pointer stars */
                    if (id_tok->type == TOKEN_PUNCTUATION && token_matches(id_tok, "*")) {
                        continue;
                    }

                    /* If we hit something else, stop */
                    break;
                }
            }
        }
    }
    return NULL;
}

/* Transform #defer declarations to cleanup attribute pattern */
void transpiler_transform_defer(ASTNode_t *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    if (!ast->children || ast->child_count == 0) {
        return;
    }

    /* Reset defer counter and clear previous generated functions */
    defer_counter = 0;
    free(generated_defer_functions);
    generated_defer_functions = NULL;
    generated_defer_functions_size = 0;

    /* Scan for #defer patterns in declarations */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (!ast->children[i]) continue;
        if (ast->children[i]->type != AST_TOKEN) continue;

        Token *tok = &ast->children[i]->token;

        /* Look for #defer preprocessor directive */
        if (tok->type != TOKEN_PREPROCESSOR) continue;
        if (!tok->text) continue;


        /* Check for #defer */
        size_t defer_len = strlen("#defer");
        if (tok->length < defer_len) continue;
        if (strncmp(tok->text, "#defer", defer_len) != 0) continue;


        /* Check it's exactly #defer, not #defer_something */
        if (tok->length > defer_len) {
            char next_char = tok->text[defer_len];
            if (next_char != ' ' && next_char != '\t' && next_char != '\r' && next_char != '\n' && next_char != '{') {
                continue;
            }
        }

        /* Extract the code block from the #defer directive */
        /* The block might span multiple tokens if it's multiline */

        /* First, check if the opening brace is in this token */
        const char *block_start = tok->text + defer_len;
        while (*block_start && (*block_start == ' ' || *block_start == '\t')) {
            block_start++;
        }

        int brace_in_token = (*block_start == '{');
        char *cleanup_code = NULL;
        size_t end_token_idx = i;

        if (brace_in_token && tok->length > (size_t)(block_start - tok->text + 1)) {
            /* Opening brace is in this token, try to find closing brace within token */
            int brace_count = 0;
            const char *code_start = block_start + 1;
            const char *block_end = code_start;

            for (const char *p = block_start; *p; p++) {
                if (*p == '{') brace_count++;
                if (*p == '}') {
                    brace_count--;
                    if (brace_count == 0) {
                        block_end = p;
                        break;
                    }
                }
            }

            if (brace_count == 0) {
                /* Complete block in single token */
                size_t code_len = block_end - code_start;
                cleanup_code = malloc(code_len + 1);
                if (!cleanup_code) continue;
                memcpy(cleanup_code, code_start, code_len);
                cleanup_code[code_len] = '\0';
            }
        }

        if (!cleanup_code) {
            /* Block spans multiple tokens - collect them */
            /* Find opening brace first */
            size_t brace_start_idx = i;
            int found_open_brace = brace_in_token;

            if (!found_open_brace) {
                /* Look forward for opening brace */
                for (size_t j = i + 1; j < ast->child_count; j++) {
                    if (!ast->children[j] || ast->children[j]->type != AST_TOKEN) continue;
                    Token *t = &ast->children[j]->token;
                    if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) continue;
                    if (t->type == TOKEN_PUNCTUATION && token_matches(t, "{")) {
                        brace_start_idx = j;
                        found_open_brace = 1;
                        break;
                    }
                    /* If we hit something else, not a defer block */
                    break;
                }
            }

            if (!found_open_brace) {
                /* Not a code block defer */
                continue;
            }

            /* Now collect tokens until we find matching closing brace */
            int brace_count = 1;
            size_t code_buffer_size = 1024;
            cleanup_code = malloc(code_buffer_size);
            if (!cleanup_code) continue;
            cleanup_code[0] = '\0';
            size_t code_len = 0;

            for (size_t j = brace_start_idx + 1; j < ast->child_count && brace_count > 0; j++) {
                if (!ast->children[j] || ast->children[j]->type != AST_TOKEN) continue;
                Token *t = &ast->children[j]->token;

                /* Check for braces */
                if (t->type == TOKEN_PUNCTUATION) {
                    if (token_matches(t, "{")) brace_count++;
                    else if (token_matches(t, "}")) {
                        brace_count--;
                        if (brace_count == 0) {
                            end_token_idx = j;
                            break;
                        }
                    }
                }

                /* Append token text to cleanup_code */
                if (t->text) {
                    size_t needed = code_len + t->length + 1;
                    if (needed > code_buffer_size) {
                        code_buffer_size = needed * 2;
                        char *new_buf = realloc(cleanup_code, code_buffer_size);
                        if (!new_buf) {
                            free(cleanup_code);
                            cleanup_code = NULL;
                            break;
                        }
                        cleanup_code = new_buf;
                    }
                    memcpy(cleanup_code + code_len, t->text, t->length);
                    code_len += t->length;
                    cleanup_code[code_len] = '\0';
                }
                end_token_idx = j;
            }

            if (!cleanup_code || brace_count != 0) {
                free(cleanup_code);
                continue;
            }
        }


        /* Extract variable name from the declaration */
        char *var_name = extract_variable_name(ast->children, ast->child_count, i);
        int is_standalone = (var_name == NULL);

        /* For standalone defer, create a dummy variable name */
        if (is_standalone) {
            var_name = malloc(64);
            if (!var_name) {
                free(cleanup_code);
                continue;
            }
            snprintf(var_name, 64, "_cz_defer_%d", defer_counter);
        }



        /* Generate cleanup function name */
        char cleanup_func_name[128];
        snprintf(cleanup_func_name, sizeof(cleanup_func_name), "_cz_cleanup_%s", var_name);

        defer_counter++;

        if (is_standalone) {
            /* For standalone defer blocks that need to access outer scope variables,
             * we need nested functions (GCC extension) or blocks (Clang extension).
             * Since these are compiler-specific, we use conditional compilation.
             *
             * GCC: Use nested functions (fully supported)
             * Clang: Use blocks if available, otherwise compile error with helpful message
             */
            char standalone_code[4096];

            /* Use nested functions with conditional compilation */
            snprintf(standalone_code, sizeof(standalone_code),
                "#ifdef __GNUC__\n"
                "#ifndef __clang__\n"
                "/* GCC: Use nested functions for scope-exit cleanup with variable capture */\n"
                "{ void %s(int *_cz_defer_var __attribute__((unused))) { %s } "
                "int __attribute__((cleanup(%s))) %s __attribute__((unused)) = 0; }\n"
                "#else\n"
                "/* Clang: Nested functions not supported. Standalone #defer blocks cannot access outer variables. */\n"
                "#error \"Standalone #defer blocks with variable capture require GCC nested functions. Use declaration-time defer instead: TYPE VAR = INIT #defer { cleanup };\"\n"
                "#endif\n"
                "#else\n"
                "#error \"Standalone #defer blocks require GCC or Clang. Compiler not supported.\"\n"
                "#endif\n",
                cleanup_func_name, cleanup_code, cleanup_func_name, var_name);

            free(tok->text);
            tok->text = strdup(standalone_code);
            tok->length = strlen(standalone_code);
            tok->type = TOKEN_IDENTIFIER;

            /* Remove tokens from i+1 to end_token_idx (inclusive) */
            if (end_token_idx > i) {
                for (size_t j = i + 1; j <= end_token_idx && j < ast->child_count; j++) {
                    if (ast->children[j] && ast->children[j]->type == AST_TOKEN) {
                        Token *t = &ast->children[j]->token;
                        free(t->text);
                        t->text = strdup("");
                        t->length = 0;
                    }
                }
            }

            free(cleanup_code);
            free(var_name);
            continue; /* Skip to next defer - no static function needed */
        }

        /* For declaration defer, generate static cleanup function and apply attribute */
        /* Generate the cleanup function */
        char func_buf[2048];
        int n;

        /* For declaration defer, replace var_name with (*var_name) */
        char modified_cleanup_code[2048];
        char *mod_code = modified_cleanup_code;
        const char *src = cleanup_code;
        size_t remaining = sizeof(modified_cleanup_code) - 1;

        /* Simple replacement: replace var_name with (*var_name) */
        while (*src && remaining > 0) {
            /* Check if we're at the start of the variable name */
            if (strncmp(src, var_name, strlen(var_name)) == 0) {
                /* Check it's not part of a larger word */
                if ((src == cleanup_code || !isalnum(src[-1])) &&
                    !isalnum(src[strlen(var_name)])) {
                    /* Replace with (*var_name) */
                    int written = snprintf(mod_code, remaining, "(*%s)", var_name);
                    if (written > 0 && (size_t)written < remaining) {
                        mod_code += written;
                        remaining -= written;
                    }
                    src += strlen(var_name);
                    continue;
                }
            }
            *mod_code++ = *src++;
            remaining--;
        }
        *mod_code = '\0';

        n = snprintf(func_buf, sizeof(func_buf),
            "static void %s(void **%s) {\n"
            "    %s\n"
            "}\n",
            cleanup_func_name, var_name, modified_cleanup_code);

        if (n < 0 || n >= (int)sizeof(func_buf)) {
            free(cleanup_code);
            free(var_name);
            continue;
        }

        /* Add to global generated functions buffer */
        size_t func_len = strlen(func_buf);
        char *new_gen_funcs = realloc(generated_defer_functions, generated_defer_functions_size + func_len + 1);
        if (!new_gen_funcs) {
            free(cleanup_code);
            free(var_name);
            continue;
        }
        generated_defer_functions = new_gen_funcs;
        memcpy(generated_defer_functions + generated_defer_functions_size, func_buf, func_len);
        generated_defer_functions_size += func_len;
        generated_defer_functions[generated_defer_functions_size] = '\0';

        /* For declaration defer, find the type token and prepend attribute */
            /* Find the type token by scanning backwards from #defer */
            size_t type_pos = 0;
            int found = 0;

            for (size_t j = i; j > 0; j--) {
                size_t idx = j - 1;
                if (!ast->children[idx] || ast->children[idx]->type != AST_TOKEN) continue;

                Token *t = &ast->children[idx]->token;

                /* Skip whitespace and comments */
                if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) continue;

                /* If we hit a semicolon or opening brace, the type should be after it */
                if (t->type == TOKEN_PUNCTUATION) {
                    if (token_matches(t, ";") || token_matches(t, "{")) {
                        /* Type should be the next non-whitespace token */
                        type_pos = skip_whitespace(ast->children, ast->child_count, idx + 1);
                        found = 1;
                        break;
                    }
                }

                /* Keep track of potential type position */
                type_pos = idx;
            }

            /* If we didn't find a ; or {, use the beginning */
            if (!found && type_pos == 0) {
                type_pos = skip_whitespace(ast->children, ast->child_count, 0);
            }

            if (type_pos >= i || !ast->children[type_pos]) {
                free(cleanup_code);
                free(var_name);
                continue;
            }

            /* Insert __attribute__((cleanup(func))) before the type */
            char attr_buf[256];
            n = snprintf(attr_buf, sizeof(attr_buf), "__attribute__((cleanup(%s))) ", cleanup_func_name);
            if (n < 0 || n >= (int)sizeof(attr_buf)) {
                free(cleanup_code);
                free(var_name);
                continue;
            }

            /* Prepend the attribute to the type token */
            Token *type_tok = &ast->children[type_pos]->token;
            if (!type_tok->text) {
                free(cleanup_code);
                free(var_name);
                continue;
            }

            size_t new_len = strlen(attr_buf) + type_tok->length + 1;
            char *new_text = malloc(new_len);
            if (!new_text) {
                free(cleanup_code);
                free(var_name);
                continue;
            }

            snprintf(new_text, new_len, "%s%s", attr_buf, type_tok->text);
            free(type_tok->text);
            type_tok->text = new_text;
            type_tok->length = strlen(new_text);

            /* Replace the #defer token with just a semicolon */
            free(tok->text);
            tok->text = strdup(";");
            tok->length = 1;
            tok->type = TOKEN_PUNCTUATION;

            /* Remove tokens from i+1 to end_token_idx (inclusive) - these are the { cleanup_code } tokens */
            if (end_token_idx > i) {
                for (size_t j = i + 1; j <= end_token_idx && j < ast->child_count; j++) {
                    if (ast->children[j] && ast->children[j]->type == AST_TOKEN) {
                        Token *t = &ast->children[j]->token;
                        free(t->text);
                        t->text = strdup("");
                        t->length = 0;
                    }
                }
            }

        free(cleanup_code);
        free(var_name);
    }
}

/* Emit generated defer cleanup functions to output */
void transpiler_emit_defer_functions(FILE *output) {
    if (generated_defer_functions && generated_defer_functions_size > 0) {
        fprintf(output, "%s\n", generated_defer_functions);
    }
}
