/*
 * CZar - C semantic authority layer
 * Transpiler defer module (transpiler/defer.c)
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

/* Helper to check if token text matches a string */
static int token_matches(Token *tok, const char *str) {
    if (!tok || !tok->text || !str) return 0;
    size_t len = strlen(str);
    return tok->length == len && strncmp(tok->text, str, len) == 0;
}

/* Helper to skip whitespace and comments */
static size_t skip_whitespace(ASTNode **children, size_t count, size_t start) {
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
static char* extract_variable_name(ASTNode **children, size_t count __attribute__((unused)), size_t defer_pos) {
    
    /* Scan backwards to find the variable identifier */
    for (size_t j = defer_pos; j > 0; j--) {
        size_t idx = j - 1;
        if (!children[idx] || children[idx]->type != AST_TOKEN) continue;
        
        Token *t = &children[idx]->token;
        
        /* Skip whitespace */
        if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) continue;
        
        
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
void transpiler_transform_defer(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    if (!ast->children || ast->child_count == 0) {
        return;
    }
    
    /* Buffer to accumulate generated cleanup functions */
    char *generated_functions = NULL;
    size_t gen_funcs_size = 0;
    
    /* Reset defer counter for each translation unit */
    defer_counter = 0;
    
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
        /* The token text is "#defer { code };" or "#defer { code }" */
        const char *block_start = tok->text + defer_len;
        while (*block_start && (*block_start == ' ' || *block_start == '\t')) {
            block_start++;
        }
        
        
        if (*block_start != '{') {
            /* Not a code block, skip */
            continue;
        }
        
        
        /* Find matching closing brace */
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
        
        
        if (brace_count != 0) {
            /* Mismatched braces */
            continue;
        }
        
        /* Extract the code between braces */
        size_t code_len = block_end - code_start;
        char *cleanup_code = malloc(code_len + 1);
        if (!cleanup_code) continue;
        memcpy(cleanup_code, code_start, code_len);
        cleanup_code[code_len] = '\0';
        
        
        /* Extract variable name from the declaration */
        char *var_name = extract_variable_name(ast->children, ast->child_count, i);
        if (!var_name) {
            free(cleanup_code);
            continue;
        }
        
        
        
        /* Generate cleanup function name */
        char cleanup_func_name[128];
        snprintf(cleanup_func_name, sizeof(cleanup_func_name), "_cz_cleanup_%s_%d", var_name, defer_counter);
        
        /* Generate the cleanup function */
        /* The function receives void **{varname} and the code uses *{varname} */
        /* We need to replace {var} with (*{var}) in the cleanup code */
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
        
        char func_buf[2048];
        int n = snprintf(func_buf, sizeof(func_buf),
            "static void %s(void **%s) {\n"
            "    %s\n"
            "}\n",
            cleanup_func_name, var_name, modified_cleanup_code);
        
        if (n < 0 || n >= (int)sizeof(func_buf)) {
            free(cleanup_code);
            free(var_name);
            continue;
        }
        
        /* Add to generated functions buffer */
        size_t func_len = strlen(func_buf);
        char *new_gen_funcs = realloc(generated_functions, gen_funcs_size + func_len + 1);
        if (!new_gen_funcs) {
            free(cleanup_code);
            free(var_name);
            continue;
        }
        generated_functions = new_gen_funcs;
        memcpy(generated_functions + gen_funcs_size, func_buf, func_len);
        gen_funcs_size += func_len;
        generated_functions[gen_funcs_size] = '\0';
        
        defer_counter++;
        
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
        
        free(cleanup_code);
        free(var_name);
    }
    
    /* Prepend generated functions to the AST */
    if (generated_functions && gen_funcs_size > 0) {
        /* Insert the generated functions at the beginning of the file */
        /* We need to insert a new token at the start */
        if (ast->child_count > 0 && ast->children[0]) {
            /* Find the first non-whitespace token */
            size_t insert_pos = 0;
            for (size_t i = 0; i < ast->child_count; i++) {
                if (!ast->children[i] || ast->children[i]->type != AST_TOKEN) continue;
                Token *t = &ast->children[i]->token;
                if (t->type != TOKEN_WHITESPACE && t->type != TOKEN_COMMENT) {
                    insert_pos = i;
                    break;
                }
            }
            
            /* Prepend to the first non-whitespace token */
            if (insert_pos < ast->child_count && ast->children[insert_pos]) {
                Token *first_tok = &ast->children[insert_pos]->token;
                if (first_tok->text) {
                    size_t new_len = strlen(generated_functions) + first_tok->length + 2;
                    char *new_text = malloc(new_len);
                    if (new_text) {
                        snprintf(new_text, new_len, "%s\n%s", generated_functions, first_tok->text);
                        free(first_tok->text);
                        first_tok->text = new_text;
                        first_tok->length = strlen(new_text);
                    }
                }
            }
        }
        free(generated_functions);
    }
}
