/*
 * CZar - C semantic authority layer
 * Log transpiler module (transpiler/log.c)
 *
 * Emits runtime logging support in generated C code.
 */

#define _POSIX_C_SOURCE 200809L

#include "log.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Check if token text matches */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) return 0;
    return strcmp(token->text, text) == 0;
}

/* Check if token text starts with prefix */
static int token_text_starts_with(Token *token, const char *prefix) {
    if (!token || !token->text || !prefix) return 0;
    return strncmp(token->text, prefix, strlen(prefix)) == 0;
}

/* Skip whitespace, comments, and empty tokens */
static size_t skip_whitespace(ASTNode **children, size_t count, size_t start) {
    for (size_t i = start; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *token = &children[i]->token;
        TokenType type = token->type;
        /* Skip whitespace, comments, and empty tokens (from method transformation) */
        if (type == TOKEN_WHITESPACE || type == TOKEN_COMMENT ||
            !token->text || token->length == 0 || token->text[0] == '\0') {
            continue;
        }
        return i;
    }
    return count;
}

/* Insert a #line directive token before the specified index */
static void insert_line_directive(ASTNode *ast, size_t index, const char *filename, int line) {
    if (!ast || index > ast->child_count) return;

    /* Create #line directive string */
    char line_directive[512];
    snprintf(line_directive, sizeof(line_directive), "\n#line %d \"%s\"\n", line, filename);

    /* Create new token node for the directive */
    ASTNode *directive_node = malloc(sizeof(ASTNode));
    if (!directive_node) return;

    directive_node->type = AST_TOKEN;
    directive_node->token.type = TOKEN_PREPROCESSOR;
    directive_node->token.text = strdup(line_directive);
    directive_node->token.length = strlen(line_directive);
    directive_node->token.line = line;
    directive_node->token.column = 1;
    directive_node->child_count = 0;
    directive_node->children = NULL;

    if (!directive_node->token.text) {
        free(directive_node);
        return;
    }

    /* Expand children array to make room */
    ASTNode **new_children = realloc(ast->children,
                                     (ast->child_count + 1) * sizeof(ASTNode*));
    if (!new_children) {
        free(directive_node->token.text);
        free(directive_node);
        return;
    }

    ast->children = new_children;

    /* Shift everything from index onwards by 1 */
    for (size_t i = ast->child_count; i > index; i--) {
        ast->children[i] = ast->children[i - 1];
    }

    /* Insert the directive */
    ast->children[index] = directive_node;
    ast->child_count++;
}

/* Expand Log calls to include correct source location via #line directives */
void transpiler_expand_log_calls(ASTNode *ast, const char *filename) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT || !filename) {
        return;
    }

    /* Scan for cz_log_* call patterns (after method transformation) */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) continue;
        if (ast->children[i]->token.type != TOKEN_IDENTIFIER) continue;

        Token *tok = &ast->children[i]->token;

        /* Check if this is a Log method call (cz_log_verbose, cz_log_debug, etc.) */
        if (token_text_starts_with(tok, "cz_log_")) {
            /* Found cz_log_* identifier, check for ( after it */
            size_t j = skip_whitespace(ast->children, ast->child_count, i + 1);
            if (j >= ast->child_count) continue;
            if (ast->children[j]->type != AST_TOKEN) continue;
            if (!token_text_equals(&ast->children[j]->token, "(")) continue;

            /* This is a Log function call - insert #line directive before it */
            int line = tok->line;
            insert_line_directive(ast, i, filename, line);

            /* Skip past the directive we just inserted */
            i++;
        }
    }
}

/* Emit Log runtime support to output */
void runtime_emit_log(FILE *output, int debug_mode) {
    if (!output) {
        return;
    }

    /* Emit Log level enum */
    fprintf(output, "/* CZar Log Runtime - Level enum */\n");
    fprintf(output, "typedef enum {\n");
    fprintf(output, "    CZ_LOG_VERBOSE = 0,\n");
    fprintf(output, "    CZ_LOG_DEBUG = 1,\n");
    fprintf(output, "    CZ_LOG_INFO = 2,\n");
    fprintf(output, "    CZ_LOG_WARN = 3,\n");
    fprintf(output, "    CZ_LOG_ERROR = 4,\n");
    fprintf(output, "    CZ_LOG_FATAL = 5\n");
    fprintf(output, "} CzLogLevel;\n\n");

    /* Emit global debug mode variable */
    fprintf(output, "/* CZar Log Runtime - Debug mode (1=only info+, 0=all levels) */\n");
    fprintf(output, "static int CZ_LOG_DEBUG_MODE = %d;\n\n", debug_mode);

    /* Emit internal helper function */
    fprintf(output, "/* CZar Log Runtime - Internal helper */\n");
    fprintf(output, "__attribute__((unused)) static void cz_log(CzLogLevel level, const char *file, int line, const char *func, const char *fmt, ...) {\n");
    fprintf(output, "    const char *level_str;\n");
    fprintf(output, "    FILE *out;\n");
    fprintf(output, "    switch (level) {\n");
    fprintf(output, "        case CZ_LOG_VERBOSE: level_str = \"VERB\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_DEBUG: level_str = \"DEBUG\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_INFO: level_str = \"INFO\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_WARN: level_str = \"WARN\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_ERROR: level_str = \"ERROR\"; out = stderr; break;\n");
    fprintf(output, "        case CZ_LOG_FATAL: level_str = \"FATAL\"; out = stderr; break;\n");
    fprintf(output, "        default: level_str = \"UNKNOWN\"; out = stdout; break;\n");
    fprintf(output, "    }\n");
    fprintf(output, "    if (CZ_LOG_DEBUG_MODE && level < CZ_LOG_INFO) return;\n");
    fprintf(output, "    \n");
    fprintf(output, "    /* Get elapsed time since program start in seconds */\n");
    fprintf(output, "    unsigned long long elapsed_ns = cz_monotonic_timer_ns();\n");
    fprintf(output, "    double elapsed_s = elapsed_ns / 1000000000.0;\n");
    fprintf(output, "    \n");
    fprintf(output, "    fprintf(out, \"[CZAR] %%.2fs %%s \", elapsed_s, level_str);\n");
    fprintf(output, "    if (func) fprintf(out, \"in %%s() \", func);\n");
    fprintf(output, "    /* Strip .c suffix from filename if present */\n");
    fprintf(output, "    const char *display_file = file ? file : \"<unknown>\";\n");
    fprintf(output, "    char file_buf[256];\n");
    fprintf(output, "    if (file) {\n");
    fprintf(output, "        size_t len = strlen(file);\n");
    fprintf(output, "        if (len > 2 && file[len-2] == '.' && file[len-1] == 'c') {\n");
    fprintf(output, "            if (len-2 < sizeof(file_buf)) {\n");
    fprintf(output, "                strncpy(file_buf, file, len-2);\n");
    fprintf(output, "                file_buf[len-2] = '\\0';\n");
    fprintf(output, "                display_file = file_buf;\n");
    fprintf(output, "            }\n");
    fprintf(output, "        }\n");
    fprintf(output, "    }\n");
    fprintf(output, "    fprintf(out, \"at %%s:%%d \", display_file, line);\n");
    fprintf(output, "    va_list args;\n");
    fprintf(output, "    va_start(args, fmt);\n");
    fprintf(output, "    vfprintf(out, fmt, args);\n");
    fprintf(output, "    va_end(args);\n");
    fprintf(output, "    fprintf(out, \"\\n\");\n");
    fprintf(output, "    fflush(out);\n");
    fprintf(output, "    if (level == CZ_LOG_FATAL) abort();\n");
    fprintf(output, "}\n\n");

    /* Emit Log struct with static method syntax support */
    fprintf(output, "/* CZar Log Runtime - Log struct for static method syntax */\n");
    fprintf(output, "typedef struct { int _unused; } Log;\n\n");

    /* Emit static method wrappers for Log struct */
    fprintf(output, "/* CZar Log Runtime - Static method wrappers */\n");
    fprintf(output, "#ifdef __GNUC__\n");
    fprintf(output, "#define cz_log_verbose(...) cz_log(CZ_LOG_VERBOSE, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_debug(...) cz_log(CZ_LOG_DEBUG, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_info(...) cz_log(CZ_LOG_INFO, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_warning(...) cz_log(CZ_LOG_WARN, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_error(...) cz_log(CZ_LOG_ERROR, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_fatal(...) cz_log(CZ_LOG_FATAL, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#else\n");
    fprintf(output, "#define cz_log_verbose(...) cz_log(CZ_LOG_VERBOSE, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_debug(...) cz_log(CZ_LOG_DEBUG, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_info(...) cz_log(CZ_LOG_INFO, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_warning(...) cz_log(CZ_LOG_WARN, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_error(...) cz_log(CZ_LOG_ERROR, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define cz_log_fatal(...) cz_log(CZ_LOG_FATAL, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#endif\n\n");
}
